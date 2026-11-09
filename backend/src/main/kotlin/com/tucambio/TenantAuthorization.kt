package com.tucambio

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationStopped
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.sql.SQLException
import java.util.Properties
import java.util.UUID
import javax.sql.DataSource

data class TenantAccess(val tenantId: UUID, val membershipId: UUID, val capabilities: Set<String>)

interface TenantAccessRepository {
    @Throws(SQLException::class)
    fun resolve(actorUserId: UUID, tenantId: UUID): TenantAccess?
}

class PostgresTenantAccessRepository private constructor(private val dataSource: DataSource) :
    TenantAccessRepository, AutoCloseable {
    override fun resolve(actorUserId: UUID, tenantId: UUID): TenantAccess? {
        dataSource.connection.use { connection ->
            connection.prepareStatement(
                "select membership_id, capability_code from public.resolve_tenant_access(?, ?)"
            ).use { statement ->
                statement.setObject(1, actorUserId)
                statement.setObject(2, tenantId)
                statement.executeQuery().use { result ->
                    var membershipId: UUID? = null
                    val capabilities = linkedSetOf<String>()
                    while (result.next()) {
                        val rowId = result.getObject("membership_id", UUID::class.java)
                        if (membershipId != null && membershipId != rowId) {
                            throw SQLException("Tenant resolver returned inconsistent membership rows")
                        }
                        membershipId = rowId
                        result.getString("capability_code")?.let(capabilities::add)
                    }
                    return membershipId?.let { TenantAccess(tenantId, it, capabilities) }
                }
            }
        }
    }

    override fun close() {
        (dataSource as? AutoCloseable)?.close()
    }

    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): PostgresTenantAccessRepository? {
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
                setProperty("socketTimeout", "5")
            }
            val config = HikariConfig().apply {
                this.jdbcUrl = jdbcUrl
                dataSourceProperties = properties
                maximumPoolSize = 5
                minimumIdle = 0
                connectionTimeout = 3_000
                validationTimeout = 1_000
                initializationFailTimeout = -1
                poolName = "tucambio-tenant-authz"
            }
            return PostgresTenantAccessRepository(HikariDataSource(config))
        }

        private fun decode(value: String): String = URLDecoder.decode(value.replace("+", "%2B"), StandardCharsets.UTF_8)
    }
}

class TenantAuthorizationService(private val repository: TenantAccessRepository) {
    fun resolve(actorUserId: UUID, tenantId: UUID): TenantAccess? = repository.resolve(actorUserId, tenantId)

    fun allows(actorUserId: UUID, tenantId: UUID, capability: String): Boolean {
        require(capability.matches(Regex("^[a-z][a-z0-9]*(\\.[a-z][a-z0-9]*)+$"))) {
            "Capability code is invalid"
        }
        return resolve(actorUserId, tenantId)?.capabilities?.contains(capability) == true
    }
}

fun Application.manageTenantAccessRepository(repository: TenantAccessRepository?) {
    if (repository is AutoCloseable) {
        monitor.subscribe(ApplicationStopped) { repository.close() }
    }
}
