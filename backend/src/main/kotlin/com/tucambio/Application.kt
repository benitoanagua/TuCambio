package com.tucambio

import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.response.respond
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
        module = Application::module
    ).start(wait = true)
}

fun Application.module() {
    install(CallLogging)
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
