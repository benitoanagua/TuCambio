package com.tucambio

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.sun.net.httpserver.HttpServer
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import java.math.BigInteger
import java.net.InetSocketAddress
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.interfaces.RSAPublicKey
import java.time.Instant
import java.util.Base64
import java.util.Date
import java.util.UUID
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SupabaseJwtAuthenticationTest {
    private lateinit var keyPair: KeyPair
    private lateinit var jwksServer: HttpServer
    private lateinit var config: SupabaseAuthConfig
    private val issuer = "http://127.0.0.1/auth/v1"
    private val audience = "authenticated"

    @BeforeTest
    fun startJwksServer() {
        keyPair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        jwksServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        jwksServer.createContext("/auth/v1/.well-known/jwks.json") { exchange ->
            val publicKey = keyPair.public as RSAPublicKey
            val body = """{"keys":[{"kty":"RSA","kid":"test-key","use":"sig","alg":"RS256","n":"${base64Url(publicKey.modulus)}","e":"${base64Url(publicKey.publicExponent)}"}]}"""
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        jwksServer.start()
        val port = jwksServer.address.port
        config = SupabaseAuthConfig(
            issuer = "http://127.0.0.1:$port/auth/v1",
            audience = audience,
            jwksUrl = "http://127.0.0.1:$port/auth/v1/.well-known/jwks.json"
        )
    }

    @AfterTest
    fun stopJwksServer() {
        jwksServer.stop(0)
    }

    @Test
    fun validAccessTokenReturnsOnlyTheAuthenticatedActorId() = testApplication {
        application { module(config) }

        val userId = UUID.randomUUID()
        val response = client.get("/api/v1/me") {
            header(HttpHeaders.Authorization, "Bearer ${token(subject = userId.toString())}")
        }

        assertEquals(HttpStatusCode.OK, response.status)
        assertTrue(response.bodyAsText().contains(userId.toString()))
        assertTrue(!response.bodyAsText().contains("email"))
    }

    @Test
    fun missingTokenIsUnauthorized() = testApplication {
        application { module(config) }
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me").status)
    }

    @Test
    fun invalidSignatureIsUnauthorized() = testApplication {
        application { module(config) }
        val otherKey = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val invalid = token(key = otherKey, subject = UUID.randomUUID().toString())
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me") {
            header(HttpHeaders.Authorization, "Bearer $invalid")
        }.status)
    }

    @Test
    fun wrongIssuerIsUnauthorized() = testApplication {
        application { module(config) }
        val invalid = token(issuer = "https://attacker.invalid/auth/v1")
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me") {
            header(HttpHeaders.Authorization, "Bearer $invalid")
        }.status)
    }

    @Test
    fun wrongAudienceIsUnauthorized() = testApplication {
        application { module(config) }
        val invalid = token(audience = "anon")
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me") {
            header(HttpHeaders.Authorization, "Bearer $invalid")
        }.status)
    }

    @Test
    fun expiredTokenIsUnauthorized() = testApplication {
        application { module(config) }
        val invalid = token(expiresAt = Instant.now().minusSeconds(60))
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me") {
            header(HttpHeaders.Authorization, "Bearer $invalid")
        }.status)
    }

    @Test
    fun missingOrMalformedSubjectIsUnauthorized() = testApplication {
        application { module(config) }
        for (subject in listOf(null, "not-a-uuid")) {
            val invalid = token(subject = subject)
            assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me") {
                header(HttpHeaders.Authorization, "Bearer $invalid")
            }.status)
        }
    }

    @Test
    fun nonAuthenticatedDatabaseRoleIsUnauthorized() = testApplication {
        application { module(config) }
        val invalid = token(role = "service_role")
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me") {
            header(HttpHeaders.Authorization, "Bearer $invalid")
        }.status)
    }

    @Test
    fun anonymousAuthIdentityIsRejected() = testApplication {
        application { module(config) }
        val invalid = token(isAnonymous = true)
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/me") {
            header(HttpHeaders.Authorization, "Bearer $invalid")
        }.status)
    }

    private fun token(
        key: KeyPair = keyPair,
        subject: String? = UUID.randomUUID().toString(),
        issuer: String = config.issuer,
        audience: String = this.audience,
        expiresAt: Instant = Instant.now().plusSeconds(300),
        role: String = "authenticated",
        isAnonymous: Boolean = false
    ): String {
        val builder = JWT.create()
            .withKeyId("test-key")
            .withIssuer(issuer)
            .withAudience(audience)
            .withClaim("role", role)
            .withClaim("is_anonymous", isAnonymous)
            .withIssuedAt(Date.from(Instant.now()))
            .withExpiresAt(Date.from(expiresAt))
        if (subject != null) builder.withSubject(subject)
        return builder.sign(Algorithm.RSA256(key.public as RSAPublicKey, key.private as java.security.interfaces.RSAPrivateKey))
    }

    private fun base64Url(value: BigInteger): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray().let {
            if (it.size > 1 && it[0] == 0.toByte()) it.copyOfRange(1, it.size) else it
        })
}
