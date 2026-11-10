package com.tucambio

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Properties
import java.util.UUID
import javax.sql.DataSource

interface FinancialReadRepository : AutoCloseable {
    fun queryOperations(actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int): JsonObject
    fun queryMovements(actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int): JsonObject
    fun queryRates(actorId: UUID, tenantId: UUID, pairId: UUID?, pageSize: Int, offset: Int): JsonObject
    fun queryEvents(actorId: UUID, tenantId: UUID, entityType: String?, entityId: UUID?, pageSize: Int, offset: Int): JsonObject
    override fun close() {}
}

class PostgresFinancialReadRepository private constructor(
    private val dataSource: DataSource
) : FinancialReadRepository {
    override fun queryOperations(
        actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int
    ) = execute(
        "select public.query_financial_operations(?, ?, ?, ?, ?)",
        actorId, tenantId, status, pageSize, offset
    )

    override fun queryMovements(
        actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int
    ) = execute(
        "select public.query_external_movements(?, ?, ?, ?, ?)",
        actorId, tenantId, status, pageSize, offset
    )

    override fun queryRates(
        actorId: UUID, tenantId: UUID, pairId: UUID?, pageSize: Int, offset: Int
    ) = executeRates(actorId, tenantId, pairId, pageSize, offset)

    override fun queryEvents(
        actorId: UUID, tenantId: UUID, entityType: String?, entityId: UUID?, pageSize: Int, offset: Int
    ): JsonObject {
        require(pageSize in 1..100 && offset in 0..10000) { "Invalid pagination window" }
        dataSource.connection.use { connection ->
            connection.prepareStatement("select public.query_financial_domain_events(?, ?, ?, ?, ?, ?)").use { statement ->
                statement.setObject(1, actorId)
                statement.setObject(2, tenantId)
                statement.setString(3, entityType)
                statement.setObject(4, entityId)
                statement.setInt(5, pageSize)
                statement.setInt(6, offset)
                statement.executeQuery().use { result ->
                    if (!result.next()) throw java.sql.SQLException("Financial event query returned no result")
                    return Json.parseToJsonElement(result.getString(1)) as? JsonObject
                        ?: throw java.sql.SQLException("Financial event query returned invalid JSON")
                }
            }
        }
    }

    private fun executeRates(
        actorId: UUID, tenantId: UUID, pairId: UUID?, pageSize: Int, offset: Int
    ): JsonObject {
        require(pageSize in 1..100 && offset in 0..10000) { "Invalid pagination window" }
        dataSource.connection.use { connection ->
            connection.prepareStatement("select public.query_currency_rates(?, ?, ?, ?, ?)").use { statement ->
                statement.setObject(1, actorId)
                statement.setObject(2, tenantId)
                statement.setObject(3, pairId)
                statement.setInt(4, pageSize)
                statement.setInt(5, offset)
                statement.executeQuery().use { result ->
                    if (!result.next()) throw java.sql.SQLException("Currency rate query returned no result")
                    return Json.parseToJsonElement(result.getString(1)) as? JsonObject
                        ?: throw java.sql.SQLException("Currency rate query returned invalid JSON")
                }
            }
        }
    }

    private fun execute(
        sql: String,
        actorId: UUID,
        tenantId: UUID,
        status: String?,
        pageSize: Int,
        offset: Int
    ): JsonObject {
        require(pageSize in 1..100 && offset in 0..10000) { "Invalid pagination window" }
        dataSource.connection.use { connection ->
            connection.prepareStatement(sql).use { statement ->
                statement.setObject(1, actorId)
                statement.setObject(2, tenantId)
                statement.setString(3, status)
                statement.setInt(4, pageSize)
                statement.setInt(5, offset)
                statement.executeQuery().use { result ->
                    if (!result.next()) throw java.sql.SQLException("Financial read query returned no result")
                    return Json.parseToJsonElement(result.getString(1)) as? JsonObject
                        ?: throw java.sql.SQLException("Financial read query returned invalid JSON")
                }
            }
        }
    }

    override fun close() { (dataSource as? AutoCloseable)?.close() }

    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): PostgresFinancialReadRepository? {
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
                setProperty("user", decode(credentials[0]))
                setProperty("password", decode(credentials[1]))
                setProperty("connectTimeout", "3")
                setProperty("socketTimeout", "10")
            }
            val config = HikariConfig().apply {
                this.jdbcUrl = jdbcUrl
                dataSourceProperties = properties
                maximumPoolSize = 5
                minimumIdle = 0
                connectionTimeout = 3_000
                validationTimeout = 1_000
                initializationFailTimeout = -1
                poolName = "tucambio-financial-reads"
            }
            return PostgresFinancialReadRepository(HikariDataSource(config))
        }

        private fun decode(value: String): String =
            URLDecoder.decode(value.replace("+", "%2B"), StandardCharsets.UTF_8)
    }
}

class FinancialReadService(private val repository: FinancialReadRepository) {
    fun operations(actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int): JsonObject {
        validate(status, pageSize, offset)
        return repository.queryOperations(actorId, tenantId, status, pageSize, offset)
    }

    fun movements(actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int): JsonObject {
        validate(status, pageSize, offset)
        return repository.queryMovements(actorId, tenantId, status, pageSize, offset)
    }

    fun rates(actorId: UUID, tenantId: UUID, pairId: UUID?, pageSize: Int, offset: Int): JsonObject {
        validate(null, pageSize, offset)
        return repository.queryRates(actorId, tenantId, pairId, pageSize, offset)
    }


    fun events(actorId: UUID, tenantId: UUID, entityType: String?, entityId: UUID?, pageSize: Int, offset: Int): JsonObject {
        if (entityType != null && entityType !in setOf("CURRENCY", "CURRENCY_PAIR", "RATE", "OPERATION", "MOVEMENT", "EVIDENCE_LINK")) {
            throw FinancialReadValidationException("invalid_entity_type")
        }
        validate(null, pageSize, offset)
        return repository.queryEvents(actorId, tenantId, entityType, entityId, pageSize, offset)
    }

    private fun validate(status: String?, pageSize: Int, offset: Int) {
        if (status != null && (status.isBlank() || status.length > 64)) {
            throw FinancialReadValidationException("invalid_status")
        }
        if (pageSize !in 1..100 || offset !in 0..10000) {
            throw FinancialReadValidationException("invalid_pagination")
        }
    }
}

class FinancialReadValidationException(val errorCode: String) : RuntimeException(errorCode)
