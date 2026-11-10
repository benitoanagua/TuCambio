package com.tucambio

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.sql.SQLException
import java.util.Properties
import java.util.UUID
import javax.sql.DataSource

@Serializable
data class LinkFinancialEvidenceRequest(
    val evidenceId: String,
    val targetType: String,
    val targetId: String
)

interface EvidenceFinancialLinkRepository : AutoCloseable {
    fun link(actorId: UUID, tenantId: UUID, request: LinkFinancialEvidenceRequest, key: String, hash: ByteArray): JsonObject
    override fun close() {}
}

class PostgresEvidenceFinancialLinkRepository private constructor(
    private val dataSource: DataSource
) : EvidenceFinancialLinkRepository {
    override fun link(
        actorId: UUID,
        tenantId: UUID,
        request: LinkFinancialEvidenceRequest,
        key: String,
        hash: ByteArray
    ): JsonObject = dataSource.connection.use { connection ->
        connection.prepareStatement(
            "select public.command_link_financial_evidence(?, ?, ?, ?, ?, ?, ?)"
        ).use { statement ->
            statement.setObject(1, actorId)
            statement.setObject(2, tenantId)
            statement.setObject(3, parseUuid(request.evidenceId))
            statement.setString(4, request.targetType.trim().uppercase())
            statement.setObject(5, parseUuid(request.targetId))
            statement.setString(6, key)
            statement.setBytes(7, hash)
            statement.executeQuery().use { result ->
                if (!result.next()) throw SQLException("Evidence link command returned no result")
                kotlinx.serialization.json.Json.parseToJsonElement(result.getString(1)) as? JsonObject
                    ?: throw SQLException("Evidence link command returned an invalid result")
            }
        }
    }

    override fun close() {
        (dataSource as? AutoCloseable)?.close()
    }

    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): PostgresEvidenceFinancialLinkRepository? {
            val rawUrl = environment["DATABASE_URL"]?.trim()?.takeIf(String::isNotEmpty) ?: return null
            val uri = URI(rawUrl)
            require(uri.scheme == "postgres" || uri.scheme == "postgresql") {
                "DATABASE_URL must use postgres:// or postgresql://"
            }
            require(!uri.host.isNullOrBlank() && uri.rawUserInfo != null && !uri.path.isNullOrBlank() && uri.path != "/") {
                "DATABASE_URL must include host, credentials and database"
            }
            require(uri.fragment == null) { "DATABASE_URL must not contain a fragment" }
            val credentials = uri.rawUserInfo.split(":", limit = 2)
            require(credentials.size == 2) { "DATABASE_URL must include username and password" }
            val jdbcUrl = buildString {
                append("jdbc:postgresql://").append(uri.host)
                if (uri.port >= 0) append(":").append(uri.port)
                append(uri.path)
                if (!uri.rawQuery.isNullOrBlank()) append("?").append(uri.rawQuery)
            }
            val properties = Properties().apply {
                setProperty("user", URLDecoder.decode(credentials[0].replace("+", "%2B"), StandardCharsets.UTF_8))
                setProperty("password", URLDecoder.decode(credentials[1].replace("+", "%2B"), StandardCharsets.UTF_8))
                setProperty("connectTimeout", "3")
                setProperty("socketTimeout", "10")
            }
            val config = HikariConfig().apply {
                this.jdbcUrl = jdbcUrl
                dataSourceProperties = properties
                maximumPoolSize = 3
                minimumIdle = 0
                connectionTimeout = 3_000
                validationTimeout = 1_000
                initializationFailTimeout = -1
                poolName = "tucambio-evidence-links"
            }
            return PostgresEvidenceFinancialLinkRepository(HikariDataSource(config))
        }
    }
}

class EvidenceFinancialLinkService(private val repository: EvidenceFinancialLinkRepository) {
    private val json = Json

    fun link(actorId: UUID, tenantId: UUID, request: LinkFinancialEvidenceRequest, key: String): JsonObject {
        parseUuid(request.evidenceId)
        parseUuid(request.targetId)
        if (request.targetType.trim().uppercase() !in setOf("OPERATION", "MOVEMENT")) {
            throw FinancialCommandValidationException("invalid_evidence_target_type")
        }
        if (key.isBlank() || key.length > 200) {
            throw FinancialCommandValidationException("invalid_idempotency_key")
        }
        val normalized = request.copy(targetType = request.targetType.trim().uppercase())
        val hash = MessageDigest.getInstance("SHA-256")
            .digest(json.encodeToString(normalized).toByteArray(StandardCharsets.UTF_8))
        return repository.link(actorId, tenantId, normalized, key, hash)
    }
}

private fun parseUuid(value: String): UUID =
    runCatching { UUID.fromString(value) }
        .getOrElse { throw FinancialCommandValidationException("invalid_uuid") }
