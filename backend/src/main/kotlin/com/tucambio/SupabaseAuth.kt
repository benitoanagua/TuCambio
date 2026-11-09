package com.tucambio

import com.auth0.jwk.JwkProviderBuilder
import io.ktor.server.application.Application
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import java.net.URI
import java.net.URL
import java.util.UUID
import java.util.concurrent.TimeUnit

data class SupabaseAuthConfig(
    val issuer: String,
    val audience: String,
    val jwksUrl: String
) {
    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): SupabaseAuthConfig? {
            val configuredUrl = environment["SUPABASE_URL"]?.trim()?.takeIf(String::isNotEmpty)
                ?: return null
            val audience = environment["SUPABASE_JWT_AUDIENCE"]?.trim()
                ?.takeIf(String::isNotEmpty) ?: "authenticated"

            val uri = URI(configuredUrl)
            require(uri.userInfo == null && uri.query == null && uri.fragment == null) {
                "SUPABASE_URL must not contain credentials, query parameters or fragments"
            }
            require(uri.path.isNullOrEmpty() || uri.path == "/") {
                "SUPABASE_URL must be the project root URL"
            }
            val localHttp = uri.scheme == "http" &&
                (uri.host == "localhost" || uri.host == "127.0.0.1" || uri.host == "::1")
            require(uri.scheme == "https" || localHttp) {
                "SUPABASE_URL must use HTTPS (HTTP is allowed only for local development)"
            }
            require(!uri.host.isNullOrBlank()) { "SUPABASE_URL must include a host" }

            val issuer = configuredUrl.trimEnd('/') + "/auth/v1"
            return SupabaseAuthConfig(
                issuer = issuer,
                audience = audience,
                jwksUrl = "$issuer/.well-known/jwks.json"
            )
        }
    }
}

fun Application.installSupabaseJwtAuthentication(config: SupabaseAuthConfig) {
    val jwkProvider = JwkProviderBuilder(URL(config.jwksUrl))
        .cached(10, 10, TimeUnit.MINUTES)
        .rateLimited(10, 1, TimeUnit.MINUTES)
        .build()

    install(Authentication) {
        jwt("supabase") {
            realm = "TuCambio API"
            verifier(jwkProvider, config.issuer) {
                withAudience(config.audience)
            }
            validate { credential ->
                val payload = credential.payload
                val subject = payload.subject
                val role = payload.getClaim("role").asString()
                val anonymous = payload.getClaim("is_anonymous").asBoolean() == true
                val validSubject = runCatching { UUID.fromString(subject) }.isSuccess

                if (validSubject && role == "authenticated" && !anonymous) {
                    JWTPrincipal(payload)
                } else {
                    null
                }
            }
        }
    }
}
