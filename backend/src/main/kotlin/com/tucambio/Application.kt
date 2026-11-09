package com.tucambio

import io.ktor.server.application.Application
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
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
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
    evidenceStorage: EvidenceObjectStorage? = null
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
        ?: SupabaseStorageConfig.fromEnvironment()?.let(::SupabaseEvidenceObjectStorage)
    effectiveEvidenceRepository?.let { repository ->
        if (repository !== evidenceRepository && repository is AutoCloseable) {
            monitor.subscribe(ApplicationStopped) { repository.close() }
        }
    }
    val evidenceWorkflow = if (effectiveEvidenceRepository != null && effectiveEvidenceStorage != null) {
        EvidenceWorkflowService(effectiveEvidenceRepository, effectiveEvidenceStorage)
    } else null

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
            post("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/complete") {
                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured"))
            }
            get("/api/v1/tenants/{tenantId}/evidence/{evidenceId}/download-url") {
                call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("authentication_not_configured"))
            }
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
                    val token = call.request.headers[HttpHeaders.Authorization]
                        ?.takeIf { it.startsWith("Bearer ", ignoreCase = true) }
                        ?.substringAfter(' ')
                    if (tenantId == null) {
                        call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_tenant_id"))
                    } else if (token.isNullOrBlank()) {
                        call.respond(HttpStatusCode.Unauthorized, ErrorResponse("missing_access_token"))
                    } else if (evidenceWorkflow == null) {
                        call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("evidence_storage_not_configured"))
                    } else {
                        try {
                            val request = call.receive<CreateEvidenceRequest>()
                            val grant = evidenceWorkflow.createUpload(actorId, tenantId, request.mimeType, request.sizeBytes, token)
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
