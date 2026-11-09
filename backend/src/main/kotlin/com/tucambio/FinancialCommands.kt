package com.tucambio

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.math.BigDecimal
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.sql.SQLException
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.Properties
import java.util.UUID
import javax.sql.DataSource

@Serializable
data class CreateCurrencyRequest(val code: String, val name: String, val decimalPlaces: Int)

@Serializable
data class CreateCurrencyPairRequest(val baseCurrencyCode: String, val quoteCurrencyCode: String)

@Serializable
data class CreateCurrencyRateRequest(
    val pairId: String,
    val buyRate: String,
    val sellRate: String,
    val validFrom: String,
    val validUntil: String? = null
)

@Serializable
data class CreateFinancialOperationRequest(
    val pairId: String,
    val sourceCurrencyCode: String,
    val targetCurrencyCode: String,
    val requestedAmount: String
)

@Serializable
data class CreateExternalMovementRequest(
    val currencyCode: String,
    val amount: String,
    val effectiveAt: String,
    val externalReference: String? = null,
    val description: String? = null
)

@Serializable
data class AssociateExternalMovementRequest(
    val operationId: String,
    val movementId: String,
    val movementRole: String
)

@Serializable
data class FinancialCommandResponse(val resourceId: String, val replayed: Boolean, val code: String? = null)

class FinancialCommandValidationException(val errorCode: String) : RuntimeException(errorCode)

interface FinancialCommandRepository : AutoCloseable {
    fun createCurrency(actorId: UUID, tenantId: UUID, request: CreateCurrencyRequest, key: String, hash: ByteArray): JsonObject
    fun createCurrencyPair(actorId: UUID, tenantId: UUID, request: CreateCurrencyPairRequest, key: String, hash: ByteArray): JsonObject
    fun createCurrencyRate(actorId: UUID, tenantId: UUID, request: CreateCurrencyRateRequest, key: String, hash: ByteArray): JsonObject
    fun createOperation(actorId: UUID, tenantId: UUID, request: CreateFinancialOperationRequest, key: String, hash: ByteArray): JsonObject
    fun createMovement(actorId: UUID, tenantId: UUID, request: CreateExternalMovementRequest, key: String, hash: ByteArray): JsonObject
    fun associateMovement(actorId: UUID, tenantId: UUID, request: AssociateExternalMovementRequest, key: String, hash: ByteArray): JsonObject
    override fun close() {}
}

class PostgresFinancialCommandRepository private constructor(private val dataSource: DataSource) : FinancialCommandRepository {
    override fun createCurrency(actorId: UUID, tenantId: UUID, request: CreateCurrencyRequest, key: String, hash: ByteArray) =
        execute("select public.command_create_tenant_currency(?, ?, ?, ?, ?, ?, ?)", actorId, tenantId, key, hash) {
            setString(3, request.code.trim())
            setString(4, request.name.trim())
            setShort(5, request.decimalPlaces.toShort())
        }

    override fun createCurrencyPair(actorId: UUID, tenantId: UUID, request: CreateCurrencyPairRequest, key: String, hash: ByteArray) =
        execute("select public.command_create_currency_pair(?, ?, ?, ?, ?, ?)", actorId, tenantId, key, hash) {
            setString(3, request.baseCurrencyCode.trim())
            setString(4, request.quoteCurrencyCode.trim())
        }

    override fun createCurrencyRate(actorId: UUID, tenantId: UUID, request: CreateCurrencyRateRequest, key: String, hash: ByteArray) =
        execute("select public.command_create_currency_rate(?, ?, ?, ?, ?, ?, ?, ?, ?)", actorId, tenantId, key, hash) {
            setObject(3, uuid(request.pairId))
            setBigDecimal(4, decimal(request.buyRate))
            setBigDecimal(5, decimal(request.sellRate))
            setObject(6, timestamp(request.validFrom))
            setObject(7, request.validUntil?.let(::timestamp))
        }

    override fun createOperation(actorId: UUID, tenantId: UUID, request: CreateFinancialOperationRequest, key: String, hash: ByteArray) =
        execute("select public.command_create_financial_operation(?, ?, ?, ?, ?, ?, ?, ?)", actorId, tenantId, key, hash) {
            setObject(3, uuid(request.pairId))
            setString(4, request.sourceCurrencyCode.trim())
            setString(5, request.targetCurrencyCode.trim())
            setBigDecimal(6, decimal(request.requestedAmount))
        }

    override fun createMovement(actorId: UUID, tenantId: UUID, request: CreateExternalMovementRequest, key: String, hash: ByteArray) =
        execute("select public.command_create_external_movement(?, ?, ?, ?, ?, ?, ?, ?, ?)", actorId, tenantId, key, hash) {
            setString(3, request.currencyCode.trim())
            setBigDecimal(4, decimal(request.amount))
            setObject(5, timestamp(request.effectiveAt))
            setString(6, request.externalReference)
            setString(7, request.description)
        }

    override fun associateMovement(actorId: UUID, tenantId: UUID, request: AssociateExternalMovementRequest, key: String, hash: ByteArray) =
        execute("select public.command_associate_external_movement(?, ?, ?, ?, ?, ?, ?)", actorId, tenantId, key, hash) {
            setObject(3, uuid(request.operationId))
            setObject(4, uuid(request.movementId))
            setString(5, request.movementRole)
        }

    private fun execute(
        sql: String,
        actorId: UUID,
        tenantId: UUID,
        key: String,
        hash: ByteArray,
        bind: java.sql.PreparedStatement.() -> Unit
    ): JsonObject {
        dataSource.connection.use { connection ->
            connection.prepareStatement(sql).use { statement ->
                statement.setObject(1, actorId)
                statement.setObject(2, tenantId)
                bind(statement)
                val last = when (sql) {
                    "select public.command_create_tenant_currency(?, ?, ?, ?, ?, ?, ?)" -> 6
                    "select public.command_create_currency_pair(?, ?, ?, ?, ?, ?)" -> 5
                    "select public.command_create_currency_rate(?, ?, ?, ?, ?, ?, ?, ?, ?)" -> 8
                    "select public.command_create_financial_operation(?, ?, ?, ?, ?, ?, ?, ?)" -> 7
                    "select public.command_create_external_movement(?, ?, ?, ?, ?, ?, ?, ?, ?)" -> 8
                    else -> 5
                }
                statement.setString(last, key)
                statement.setBytes(last + 1, hash)
                statement.executeQuery().use { result ->
                    if (!result.next()) throw SQLException("Financial command returned no result")
                    return Json.parseToJsonElement(result.getString(1)) as? JsonObject
                        ?: throw SQLException("Financial command returned an invalid result")
                }
            }
        }
    }

    override fun close() { (dataSource as? AutoCloseable)?.close() }

    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): PostgresFinancialCommandRepository? {
            val rawUrl = environment["DATABASE_URL"]?.trim()?.takeIf(String::isNotEmpty) ?: return null
            val uri = URI(rawUrl)
            require(uri.scheme == "postgres" || uri.scheme == "postgresql") { "DATABASE_URL must use postgres:// or postgresql://" }
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
                poolName = "tucambio-financial-commands"
            }
            return PostgresFinancialCommandRepository(HikariDataSource(config))
        }

        private fun decode(value: String): String =
            URLDecoder.decode(value.replace("+", "%2B"), StandardCharsets.UTF_8)
    }
}

class FinancialCommandService(private val repository: FinancialCommandRepository) {
    private val json = Json

    fun createCurrency(actor: UUID, tenant: UUID, request: CreateCurrencyRequest, key: String) =
        repository.createCurrency(actor, tenant, request, key, hash(request))

    fun createCurrencyPair(actor: UUID, tenant: UUID, request: CreateCurrencyPairRequest, key: String) =
        repository.createCurrencyPair(actor, tenant, request, key, hash(request))

    fun createCurrencyRate(actor: UUID, tenant: UUID, request: CreateCurrencyRateRequest, key: String) =
        repository.createCurrencyRate(actor, tenant, request, key, hash(request))

    fun createOperation(actor: UUID, tenant: UUID, request: CreateFinancialOperationRequest, key: String) =
        repository.createOperation(actor, tenant, request, key, hash(request))

    fun createMovement(actor: UUID, tenant: UUID, request: CreateExternalMovementRequest, key: String) =
        repository.createMovement(actor, tenant, request, key, hash(request))

    fun associateMovement(actor: UUID, tenant: UUID, request: AssociateExternalMovementRequest, key: String) =
        repository.associateMovement(actor, tenant, request, key, hash(request))

    private inline fun <reified T> hash(request: T): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(json.encodeToString(request).toByteArray(StandardCharsets.UTF_8))
}

private fun uuid(value: String): UUID =
    runCatching { UUID.fromString(value) }.getOrElse { throw FinancialCommandValidationException("invalid_uuid") }

private fun decimal(value: String): BigDecimal =
    runCatching { BigDecimal(value) }.getOrElse { throw FinancialCommandValidationException("invalid_decimal") }

private fun timestamp(value: String): OffsetDateTime =
    runCatching { OffsetDateTime.parse(value).withOffsetSameInstant(ZoneOffset.UTC) }
        .getOrElse { throw FinancialCommandValidationException("invalid_timestamp") }
