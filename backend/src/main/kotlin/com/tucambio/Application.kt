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
import io.ktor.http.HttpStatusCode
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    require(port in 1..65535) { "PORT must be between 1 and 65535" }

    embeddedServer(
        factory = Netty,
        host = "0.0.0.0",
        port = port,
        module = { module() }
    ).start(wait = true)
}

fun Application.module(authConfig: SupabaseAuthConfig? = SupabaseAuthConfig.fromEnvironment()) {
    install(CallLogging)
    authConfig?.let(::installSupabaseJwtAuthentication)
    install(ContentNegotiation) {
        json(
            Json {
                explicitNulls = false
                ignoreUnknownKeys = true
            }
        )
    }

    routing {
        get("/") {
            call.respond(
                ServiceInfo(
                    service = "tucambio-api",
                    status = "ok"
                )
            )
        }

        get("/health/live") {
            call.respond(HealthResponse(status = "ok"))
        }

        // Until external dependencies are wired, readiness means the HTTP process is initialized.
        get("/health/ready") {
            call.respond(HealthResponse(status = "ready"))
        }

        if (authConfig == null) {
            get("/api/v1/me") {
                call.respond(
                    HttpStatusCode.ServiceUnavailable,
                    ErrorResponse(error = "authentication_not_configured")
                )
            }
        } else {
            authenticate("supabase") {
                get("/api/v1/me") {
                    val principal = call.principal<JWTPrincipal>()
                    call.respond(ActorResponse(userId = requireNotNull(principal).payload.subject))
                }
            }
        }
    }
}

@Serializable
data class ServiceInfo(
    val service: String,
    val status: String
)

@Serializable
data class HealthResponse(
    val status: String
)

@Serializable
data class ActorResponse(
    val userId: String
)

@Serializable
data class ErrorResponse(
    val error: String
)
