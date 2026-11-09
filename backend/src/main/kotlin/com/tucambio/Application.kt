package com.tucambio

import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationStopped
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.install
import io.ktor.server.auth.authenticate
import io.ktor.server.auth.principal
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.response.respond
import io.ktor.server.request.receive
import io.ktor.http.HttpStatusCode
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonPrimitive
import java.sql.SQLException
import java.util.UUID

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    require(port in 1..65535) { "PORT must be between 1 and 65535" }
    embeddedServer(factory = Netty, host = "0.0.0.0", port = port, module = { module() }).start(wait = true)
}

fun Application.module(
    authConfig: SupabaseAuthConfig? = SupabaseAuthConfig.fromEnvironment(),
    tenantAccessRepository: TenantAccessRepository? = null,
    evidenceRepository: EvidenceRepository? = null,
    evidenceStorage: EvidenceObjectStorage? = null,
    evidenceReviewRepository: EvidenceReviewRepository? = null,
    financialCommandRepository: FinancialCommandRepository? = null
) {
    install(CallLogging)
    authConfig?.let(::installSupabaseJwtAuthentication)
    val effectiveRepository = tenantAccessRepository
        ?: if (authConfig != null) PostgresTenantAccessRepository.fromEnvironment() else null
    val authorization = effectiveRepository?.let(::TenantAuthorizationService)
    manageTenantAccessRepository(effectiveRepository)
    val effectiveEvidenceRepository = evidenceRepository
        ?: if (authConfig != null) PostgresEvidenceRepository.fromEnvironment() else null
    val effectiveEvidenceStorage = evidenceStorage
        ?: if (authConfig != null) {
            SupabaseStorageConfig.fromEnvironment()?.let { SupabaseEvidenceObjectStorage(it) }
        } else null
    if (effectiveEvidenceRepository != null && evidenceRepository == null) {
        monitor.subscribe(ApplicationStopped) { effectiveEvidenceRepository.close() }
    }
    val evidenceWorkflow = if (effectiveEvidenceRepository != null && effectiveEvidenceStorage != null) {
        EvidenceWorkflowService(effectiveEvidenceRepository, effectiveEvidenceStorage)
    } else null
    val effectiveEvidenceReviewRepository = evidenceReviewRepository
        ?: if (authConfig != null) PostgresEvidenceReviewRepository.fromEnvironment() else null
    val evidenceReview = effectiveEvidenceReviewRepository?.let(::EvidenceReviewService)
    if (effectiveEvidenceReviewRepository != null && evidenceReviewRepository == null) {
        monitor.subscribe(ApplicationStopped) { effectiveEvidenceReviewRepository.close() }
    }
    val effectiveFinancialCommandRepository = financialCommandRepository
        ?: if (authConfig != null) PostgresFinancialCommandRepository.fromEnvironment() else null
    val financialCommands = effectiveFinancialCommandRepository?.let(::FinancialCommandService)
    if (effectiveFinancialCommandRepository != null && financialCommandRepository == null) {
        monitor.subscribe(ApplicationStopped) { effectiveFinancialCommandRepository.close() }
    }

    install(ContentNegotiation) {
        json(Json { explicitNulls = false; ignoreUnknownKeys = true })
    }

    routing {
        get("/") { call.respond(ServiceInfo("tucambio-api", "ok")) }
        get("/health/live") { call.respond(HealthResponse("ok")) }
        get("/health/ready") { call.respond(HealthResponse("ready")) }

        if (authConfig == null) {
            get("/api/v1/me") {
                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured"))
            }
            get("/api/v1/tenants/{tenantId}/authorization") {
                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured"))
            }
            post("/api/v1/tenants/{tenantId}/evidence") {
                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured"))
            }
            post("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/review") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
            post("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/complete") {
                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured"))
            }
            get("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/download-url") {
                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured"))
            }
            post("/api/v1/tenants/{tenantId}/currencies") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
            post("/api/v1/tenants/{tenantId}/currency-pairs") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
            post("/api/v1/tenants/{tenantId}/currency-rates") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
            post("/api/v1/tenants/{tenantId}/operations") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
            post("/api/v1/tenants/{tenantId}/movements") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
            post("/api/v1/tenants/{tenantId}/movement-associations") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
            post("/api/v1/tenants/{tenantId}/movements/{movementId}/transitions") { call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured")) }
        } else {
            authenticate("supabase") {
                get("/api/v1/me") {
                    val principal = call.principal<JWTPrincipal>()
                    call.respond(ActorResponse(requireNotNull(principal).payload.subject))
                }
                get("/api/v1/tenants/{tenantId}/authorization") {
                    val actorId = UUID.fromString(requireNotNull(call.principal<JWTPrincipal>()).payload.subject)
                    val tenantId = call.parameters["tenantId"]
                        ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    if (tenantId == null) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_tenant_id"))
                    } else if (authorization == null) {
                        call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("database_not_configured"))
                    } else {
                        try {
                            val access = authorization.resolve(actorId, tenantId)
                            if (access == null) {
                                call.respond(HttpStatusCode.Forbidden, ErrorResponse("tenant_access_denied"))
                            } else {
                                call.respond(TenantAuthorizationResponse(
                                    access.tenantId.toString(),
                                    access.membershipId.toString(),
                                    access.capabilities.sorted()
                                ))
                            }
                        } catch (_: SQLException) {
                            call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authorization_unavailable"))
                        }
                    }
                }
                post("/api/v1/tenants/{tenantId}/evidence") {
                    val actorId = UUID.fromString(requireNotNull(call.principal<JWTPrincipal>()).payload.subject)
                    val tenantId = call.parameters["tenantId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    if (tenantId == null) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_tenant_id"))
                    } else if (evidenceWorkflow == null) {
                        call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_storage_not_configured"))
                    } else {
                        try {
                            val request = call.receive<CreateEvidenceRequest>()
                            val grant = evidenceWorkflow.createUpload(actorId, tenantId, request.mimeType, request.sizeBytes)
                            call.respond(HttpStatusCode.Created, grant)
                        } catch (_: EvidenceValidationException) {
                            call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_evidence_declaration"))
                        } catch (e: SQLException) {
                            if (e.sqlState == "42501") {
                                call.respond(HttpStatusCode.Forbidden, ErrorResponse("tenant_access_denied"))
                            } else {
                                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_service_unavailable"))
                            }
                        } catch (_: IllegalStateException) {
                            call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_storage_unavailable"))
                        }
                    }
                }
                post("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/review") {
                    val tenantId = call.parameters["tenantId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    val evidenceId = call.parameters["evidenceId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    val actorId = UUID.fromString(requireNotNull(call.principal<JWTPrincipal>()).payload.subject)
                    val key = call.request.headers["Idempotency-Key"]
                    if (tenantId == null || evidenceId == null) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_evidence_reference"))
                    } else if (key.isNullOrBlank() || key.length > 200) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_idempotency_key"))
                    } else if (evidenceReview == null) {
                        call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_review_not_configured"))
                    } else {
                        try {
                            val result = evidenceReview.review(actorId, tenantId, evidenceId, call.receive<ReviewEvidenceRequest>(), key)
                            val resourceId = result["resourceId"]?.jsonPrimitive?.content
                            val replayed = result["replayed"]?.jsonPrimitive?.content?.toBooleanStrictOrNull() ?: false
                            if (resourceId == null) call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_review_invalid_response"))
                            else call.respond(if (replayed) HttpStatusCode.OK else HttpStatusCode.OK, result)
                        } catch (e: SQLException) {
                            when (e.sqlState) {
                                "42501" -> call.respond(HttpStatusCode.Forbidden, ErrorResponse("tenant_access_denied"))
                                "23505" -> call.respond(HttpStatusCode.Conflict, ErrorResponse("evidence_review_conflict"))
                                "23503" -> call.respond(HttpStatusCode.NotFound, ErrorResponse("available_evidence_not_found"))
                                "23514", "22023" -> call.respond(HttpStatusCode.UnprocessableEntity, ErrorResponse("invalid_evidence_review_transition"))
                                else -> call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_review_unavailable"))
                            }
                        }
                    }
                }
                post("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/complete") {
                    val actorId = UUID.fromString(requireNotNull(call.principal<JWTPrincipal>()).payload.subject)
                    val tenantId = call.parameters["tenantId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    val evidenceId = call.parameters["evidenceId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    if (tenantId == null || evidenceId == null) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_evidence_reference"))
                    } else if (evidenceWorkflow == null) {
                        call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_storage_not_configured"))
                    } else {
                        try {
                            val completed = evidenceWorkflow.complete(actorId, tenantId, evidenceId)
                            if (completed) {
                                call.respond(EvidenceCompleteResponse(evidenceId.toString(), "available"))
                            } else {
                                call.respond(HttpStatusCode.NotFound, ErrorResponse("pending_evidence_not_found"))
                            }
                        } catch (_: EvidenceValidationException) {
                            call.respond(HttpStatusCode.UnprocessableEntity, ErrorResponse("evidence_content_invalid"))
                        } catch (e: SQLException) {
                            if (e.sqlState == "42501") {
                                call.respond(HttpStatusCode.Forbidden, ErrorResponse("tenant_access_denied"))
                            } else {
                                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_service_unavailable"))
                            }
                        } catch (_: IllegalStateException) {
                            call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_storage_unavailable"))
                        }
                    }
                }
                post("/api/v1/tenants/{tenantId}/currencies") {
                    if (financialCommands == null) call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_commands_not_configured"))
                    else call.executeFinancialCommand { actor, tenant, key ->
                        financialCommands.createCurrency(actor, tenant, call.receive<CreateCurrencyRequest>(), key)
                    }
                }
                post("/api/v1/tenants/{tenantId}/currency-pairs") {
                    if (financialCommands == null) call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_commands_not_configured"))
                    else call.executeFinancialCommand { actor, tenant, key ->
                        financialCommands.createCurrencyPair(actor, tenant, call.receive<CreateCurrencyPairRequest>(), key)
                    }
                }
                post("/api/v1/tenants/{tenantId}/currency-rates") {
                    if (financialCommands == null) call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_commands_not_configured"))
                    else call.executeFinancialCommand { actor, tenant, key ->
                        financialCommands.createCurrencyRate(actor, tenant, call.receive<CreateCurrencyRateRequest>(), key)
                    }
                }
                post("/api/v1/tenants/{tenantId}/operations") {
                    if (financialCommands == null) call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_commands_not_configured"))
                    else call.executeFinancialCommand { actor, tenant, key ->
                        financialCommands.createOperation(actor, tenant, call.receive<CreateFinancialOperationRequest>(), key)
                    }
                }
                post("/api/v1/tenants/{tenantId}/movements") {
                    if (financialCommands == null) call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_commands_not_configured"))
                    else call.executeFinancialCommand { actor, tenant, key ->
                        financialCommands.createMovement(actor, tenant, call.receive<CreateExternalMovementRequest>(), key)
                    }
                }
                post("/api/v1/tenants/{tenantId}/movement-associations") {
                    if (financialCommands == null) call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_commands_not_configured"))
                    else call.executeFinancialCommand { actor, tenant, key ->
                        financialCommands.associateMovement(actor, tenant, call.receive<AssociateExternalMovementRequest>(), key)
                    }
                }
                post("/api/v1/tenants/{tenantId}/movements/{movementId}/transitions") {
                    val movementId = call.parameters["movementId"]
                    if (movementId == null || runCatching { UUID.fromString(movementId) }.isFailure) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_movement_id"))
                    } else if (financialCommands == null) {
                        call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_commands_not_configured"))
                    } else {
                        call.executeFinancialCommand { actor, tenant, key ->
                            financialCommands.transitionMovement(actor, tenant, movementId, call.receive<TransitionExternalMovementRequest>(), key)
                        }
                    }
                }
                get("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/download-url") {
                    val actorId = UUID.fromString(requireNotNull(call.principal<JWTPrincipal>()).payload.subject)
                    val tenantId = call.parameters["tenantId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    val evidenceId = call.parameters["evidenceId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    if (tenantId == null || evidenceId == null) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_evidence_reference"))
                    } else if (evidenceWorkflow == null) {
                        call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_storage_not_configured"))
                    } else {
                        try {
                            val grant = evidenceWorkflow.createDownloadUrl(actorId, tenantId, evidenceId)
                            if (grant == null) {
                                call.respond(HttpStatusCode.NotFound, ErrorResponse("available_evidence_not_found"))
                            } else {
                                call.respond(grant)
                            }
                        } catch (e: SQLException) {
                            if (e.sqlState == "42501") {
                                call.respond(HttpStatusCode.Forbidden, ErrorResponse("tenant_access_denied"))
                            } else {
                                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_service_unavailable"))
                            }
                        } catch (_: IllegalStateException) {
                            call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_storage_unavailable"))
                        }
                    }
                }
            }
        }
    }
}

@Serializable data class ServiceInfo(val service: String, val status: String)
@Serializable data class HealthResponse(val status: String)
@Serializable data class ActorResponse(val userId: String)
@Serializable data class TenantAuthorizationResponse(
    val tenantId: String,
    val membershipId: String,
    val capabilities: List<String>
)
@Serializable data class ErrorResponse(val error: String)

private suspend fun ApplicationCall.executeFinancialCommand(
    command: suspend (UUID, UUID, String) -> kotlinx.serialization.json.JsonObject
) {
    val tenantId = parameters["tenantId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    if (tenantId == null) {
        respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_tenant_id"))
        return
    }
    val key = request.headers["Idempotency-Key"]
    if (key.isNullOrBlank() || key.length > 200) {
        respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_idempotency_key"))
        return
    }
    val actorId = runCatching {
        UUID.fromString(requireNotNull(principal<JWTPrincipal>()).payload.subject)
    }.getOrNull()
    if (actorId == null) {
        respond(HttpStatusCode.Unauthorized, ErrorResponse("invalid_actor"))
        return
    }
    try {
        val result = command(actorId, tenantId, key)
        val resourceId = result["resourceId"]?.jsonPrimitive?.content
        val replayed = result["replayed"]?.jsonPrimitive?.content?.toBooleanStrictOrNull() ?: false
        if (resourceId == null) {
            respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_command_invalid_response"))
        } else {
            val code = result["code"]?.jsonPrimitive?.content
            val status = result["status"]?.jsonPrimitive?.content
            respond(if (replayed) HttpStatusCode.OK else HttpStatusCode.Created,
                FinancialCommandResponse(resourceId, replayed, code, status))
        }
    } catch (e: FinancialCommandValidationException) {
        respond(HttpStatusCode.BadRequest, ErrorResponse(e.errorCode))
    } catch (e: SQLException) {
        when (e.sqlState) {
            "42501" -> respond(HttpStatusCode.Forbidden, ErrorResponse("tenant_access_denied"))
            "23505" -> respond(HttpStatusCode.Conflict, ErrorResponse("financial_command_conflict"))
            "23503" -> respond(HttpStatusCode.Conflict, ErrorResponse("financial_reference_conflict"))
            "23514", "22023", "22003", "22P02" -> respond(HttpStatusCode.UnprocessableEntity, ErrorResponse("financial_command_invalid"))
            else -> respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("financial_command_unavailable"))
        }
    } catch (_: IllegalArgumentException) {
        respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_financial_command"))
    }
}
