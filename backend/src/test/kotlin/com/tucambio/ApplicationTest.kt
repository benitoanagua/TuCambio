package com.tucambio

import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals

class ApplicationTest {
    @Test
    fun livenessEndpointReturnsOk() = testApplication {
        application { module() }

        val response = client.get("/health/live")

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals("""{"status":"ok"}""", response.bodyAsText())
    }

    @Test
    fun readinessEndpointReturnsReady() = testApplication {
        application { module() }

        val response = client.get("/health/ready")

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals("""{"status":"ready"}""", response.bodyAsText())
    }

    @Test
    fun protectedIdentityEndpointFailsClosedWhenSupabaseIsNotConfigured() = testApplication {
        application { module(authConfig = null) }

        val response = client.get("/api/v1/me")

        assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        assertEquals("""{"error":"authentication_not_configured"}""", response.bodyAsText())
    }

    @Test
    fun evidenceEndpointsFailClosedWhenAuthenticationIsNotConfigured() = testApplication {
        application { module(authConfig = null) }

        val response = client.get(
            "/api/v1/tenants/52000000-0000-0000-0000-000000000001/evidence/" +
                "56000000-0000-0000-0000-000000000001/download-url"
        )

        assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        assertEquals("""{"error":"authentication_not_configured"}""", response.bodyAsText())
    }

    @Test
    fun financialCommandEndpointsFailClosedWhenAuthenticationIsNotConfigured() = testApplication {
        application { module(authConfig = null) }
        val tenant = "52000000-0000-0000-0000-000000000001"
        val paths = listOf(
            "/api/v1/tenants/$tenant/currencies",
            "/api/v1/tenants/$tenant/currency-pairs",
            "/api/v1/tenants/$tenant/currency-rates",
            "/api/v1/tenants/$tenant/operations",
            "/api/v1/tenants/$tenant/movements",
            "/api/v1/tenants/$tenant/movement-associations"
        )
        paths.forEach { path ->
            assertEquals(HttpStatusCode.ServiceUnavailable, client.post(path).status)
        }
        assertEquals(
            HttpStatusCode.ServiceUnavailable,
            client.get("/api/v1/tenants/$tenant/operations").status
        )
        assertEquals(
            HttpStatusCode.ServiceUnavailable,
            client.get("/api/v1/tenants/$tenant/movements").status
        )
    }

    @Test
    fun rootEndpointIdentifiesService() = testApplication {
        application { module() }

        val response = client.get("/")

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals(
            """{"service":"tucambio-api","status":"ok"}""",
            response.bodyAsText()
        )
    }
}
