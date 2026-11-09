package com.tucambio

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Duration
import java.util.UUID
import javax.sql.DataSource
import java.sql.SQLException

private const val EVIDENCE_BUCKET = "operation-evidence"
private const val MAX_EVIDENCE_BYTES = 10L * 1024 * 1024
private val ALLOWED_EVIDENCE_MIME_TYPES = setOf(
    "application/pdf", "image/jpeg", "image/png", "image/webp"
)

data class EvidenceRecord(
    val id: UUID,
    val bucketId: String,
    val objectPath: String,
    val mimeType: String,
    val expectedSizeBytes: Long
)

data class AvailableEvidence(val record: EvidenceRecord, val sha256: ByteArray)

interface EvidenceRepository : AutoCloseable {
    fun createPending(actorUserId: UUID, tenantId: UUID, evidenceId: UUID, mimeType: String, expectedSizeBytes: Long): EvidenceRecord
    fun findPending(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): EvidenceRecord?
    fun complete(actorUserId: UUID, tenantId: UUID, evidenceId: UUID, sha256: ByteArray): Boolean
    fun findAvailable(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): AvailableEvidence?
    override fun close() {}
}

class PostgresEvidenceRepository private constructor(private val dataSource: DataSource) : EvidenceRepository {
    override fun createPending(actorUserId: UUID, tenantId: UUID, evidenceId: UUID, mimeType: String, expectedSizeBytes: Long): EvidenceRecord =
        dataSource.connection.use { connection ->
            connection.prepareStatement(
                "select evidence_id, bucket_id, object_path from public.create_tenant_evidence(?, ?, ?, ?, ?)"
            ).use { statement ->
                statement.setObject(1, actorUserId)
                statement.setObject(2, tenantId)
                statement.setObject(3, evidenceId)
                statement.setString(4, mimeType)
                statement.setLong(5, expectedSizeBytes)
                statement.executeQuery().use { result ->
                    if (!result.next()) throw SQLException("Evidence creation returned no row")
                    EvidenceRecord(evidenceId, result.getString("bucket_id"), result.getString("object_path"), mimeType, expectedSizeBytes)
                }
            }
        }

    override fun findPending(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): EvidenceRecord? =
        findRecord(
            "select evidence_id, bucket_id, object_path, mime_type, expected_size_bytes from public.get_pending_tenant_evidence_for_upload(?, ?, ?)",
            actorUserId, tenantId, evidenceId
        )

    override fun complete(actorUserId: UUID, tenantId: UUID, evidenceId: UUID, sha256: ByteArray): Boolean =
        dataSource.connection.use { connection ->
            connection.prepareStatement("select public.complete_tenant_evidence(?, ?, ?, ?)").use { statement ->
                statement.setObject(1, actorUserId)
                statement.setObject(2, tenantId)
                statement.setObject(3, evidenceId)
                statement.setBytes(4, sha256)
                statement.executeQuery().use { result -> result.next() && result.getBoolean(1) }
            }
        }

    override fun findAvailable(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): AvailableEvidence? =
        dataSource.connection.use { connection ->
            connection.prepareStatement(
                "select evidence_id, bucket_id, object_path, mime_type, expected_size_bytes, sha256 " +
                    "from public.get_tenant_evidence_for_download(?, ?, ?)"
            ).use { statement ->
                statement.setObject(1, actorUserId)
                statement.setObject(2, tenantId)
                statement.setObject(3, evidenceId)
                statement.executeQuery().use { result ->
                    if (!result.next()) return@use null
                    val record = EvidenceRecord(
                        result.getObject("evidence_id", UUID::class.java),
                        result.getString("bucket_id"),
                        result.getString("object_path"),
                        result.getString("mime_type"),
                        result.getLong("expected_size_bytes")
                    )
                    AvailableEvidence(record, result.getBytes("sha256"))
                }
            }
        }

    private fun findRecord(sql: String, actorUserId: UUID, tenantId: UUID, evidenceId: UUID): EvidenceRecord? =
        dataSource.connection.use { connection ->
            connection.prepareStatement(sql).use { statement ->
                statement.setObject(1, actorUserId)
                statement.setObject(2, tenantId)
                statement.setObject(3, evidenceId)
                statement.executeQuery().use { result ->
                    if (!result.next()) return@use null
                    EvidenceRecord(
                        result.getObject("evidence_id", UUID::class.java),
                        result.getString("bucket_id"),
                        result.getString("object_path"),
                        result.getString("mime_type"),
                        result.getLong("expected_size_bytes")
                    )
                }
            }
        }

    override fun close() { (dataSource as? AutoCloseable)?.close() }

    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): PostgresEvidenceRepository? {
            val rawUrl = environment["DATABASE_URL"]?.trim()?.takeIf(String::isNotEmpty) ?: return null
            val uri = URI(rawUrl)
            require(uri.scheme == "postgres" || uri.scheme == "postgresql") { "DATABASE_URL must use postgres:// or postgresql://" }
            require(!uri.host.isNullOrBlank() && uri.rawUserInfo != null && !uri.path.isNullOrBlank() && uri.path != "/") {
                "DATABASE_URL must include host, credentials and database"
            }
            val credentials = uri.rawUserInfo.split(":", limit = 2)
            require(credentials.size == 2) { "DATABASE_URL must include username and password" }
            val jdbcUrl = buildString {
                append("jdbc:postgresql://").append(uri.host)
                if (uri.port >= 0) append(":").append(uri.port)
                append(uri.path)
                if (!uri.rawQuery.isNullOrBlank()) append("?").append(uri.rawQuery)
            }
            val config = HikariConfig().apply {
                this.jdbcUrl = jdbcUrl
                username = decodeDatabaseCredential(credentials[0])
                password = decodeDatabaseCredential(credentials[1])
                maximumPoolSize = 5
                minimumIdle = 0
                connectionTimeout = 3_000
                validationTimeout = 1_000
                initializationFailTimeout = -1
                poolName = "tucambio-evidence"
            }
            return PostgresEvidenceRepository(HikariDataSource(config))
        }

        private fun decodeDatabaseCredential(value: String): String =
            java.net.URLDecoder.decode(value.replace("+", "%2B"), StandardCharsets.UTF_8)
    }
}

data class SupabaseStorageConfig(val projectUrl: String, val serviceRoleKey: String) {
    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): SupabaseStorageConfig? {
            val url = environment["SUPABASE_URL"]?.trim()?.takeIf(String::isNotEmpty) ?: return null
            val service = environment["SUPABASE_SERVICE_ROLE_KEY"]?.trim()?.takeIf(String::isNotEmpty) ?: return null
            val uri = URI(url)
            val localHttp = uri.scheme == "http" && uri.host in setOf("localhost", "127.0.0.1", "::1")
            require(uri.scheme == "https" || localHttp) { "SUPABASE_URL must use HTTPS outside local development" }
            require(!uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null) {
                "SUPABASE_URL must be a project root URL without credentials, query or fragment"
            }
            require(uri.path.isNullOrEmpty() || uri.path == "/") { "SUPABASE_URL must be a project root URL" }
            return SupabaseStorageConfig(url.trimEnd('/'), service)
        }
    }
}

interface EvidenceObjectStorage {
    fun createSignedUploadUrl(objectPath: String): String
    fun downloadObject(objectPath: String): ByteArray
    fun createSignedDownloadUrl(objectPath: String, expiresInSeconds: Int = 60): String
}

class SupabaseEvidenceObjectStorage(
    private val config: SupabaseStorageConfig,
    private val http: HttpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(3))
        .followRedirects(HttpClient.Redirect.NEVER)
        .build()
) : EvidenceObjectStorage {
    override fun createSignedUploadUrl(objectPath: String): String {
        requireValidObjectPath(objectPath)
        val response = send(
            HttpRequest.newBuilder(storageUri("/object/upload/sign/$EVIDENCE_BUCKET/$objectPath"))
                .timeout(Duration.ofSeconds(5))
                .header("apikey", config.serviceRoleKey)
                .header("Authorization", "Bearer ${config.serviceRoleKey}")
                .POST(HttpRequest.BodyPublishers.noBody())
                .build()
        )
        ensureSuccess(response, "Could not create signed upload URL")
        val signed = Json.parseToJsonElement(response.body().toString(StandardCharsets.UTF_8))
            .jsonObject["signedURL"]?.jsonPrimitive?.content
            ?: throw IllegalStateException("Storage did not return a signed upload URL")
        return absoluteStorageUrl(signed)
    }

    override fun downloadObject(objectPath: String): ByteArray {
        requireValidObjectPath(objectPath)
        val response = http.send(
            HttpRequest.newBuilder(storageUri("/object/$EVIDENCE_BUCKET/$objectPath"))
                .timeout(Duration.ofSeconds(10))
                .header("apikey", config.serviceRoleKey)
                .header("Authorization", "Bearer ${config.serviceRoleKey}")
                .GET()
                .build(),
            HttpResponse.BodyHandlers.ofInputStream()
        )
        if (response.statusCode() !in 200..299) {
            response.body().close()
            throw IllegalStateException("Storage object download failed with HTTP ${response.statusCode()}")
        }
        return response.body().use { input ->
            val bytes = input.readNBytes((MAX_EVIDENCE_BYTES + 1).toInt())
            if (bytes.size.toLong() > MAX_EVIDENCE_BYTES) throw EvidenceValidationException("Evidence exceeds the 10 MiB limit")
            bytes
        }
    }

    override fun createSignedDownloadUrl(objectPath: String, expiresInSeconds: Int): String {
        requireValidObjectPath(objectPath)
        require(expiresInSeconds in 30..300) { "Download URL lifetime must be between 30 and 300 seconds" }
        val body = buildJsonObject { put("expiresIn", expiresInSeconds) }.toString()
        val response = send(
            HttpRequest.newBuilder(storageUri("/object/sign/$EVIDENCE_BUCKET/$objectPath"))
                .timeout(Duration.ofSeconds(5))
                .header("apikey", config.serviceRoleKey)
                .header("Authorization", "Bearer ${config.serviceRoleKey}")
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build()
        )
        ensureSuccess(response, "Could not create signed download URL")
        val signed = Json.parseToJsonElement(response.body().toString(StandardCharsets.UTF_8))
            .jsonObject["signedURL"]?.jsonPrimitive?.content
            ?: throw IllegalStateException("Storage did not return a signed download URL")
        return absoluteStorageUrl(signed)
    }

    private fun storageUri(path: String): URI = URI.create("${config.projectUrl}/storage/v1$path")

    private fun absoluteStorageUrl(signedUrl: String): String {
        val project = URI.create(config.projectUrl)
        val result = if (signedUrl.startsWith("https://") || signedUrl.startsWith("http://")) {
            URI.create(signedUrl)
        } else {
            val suffix = if (signedUrl.startsWith("/storage/v1/")) signedUrl else "/storage/v1/$${signedUrl.trimStart('/')}"
            URI.create("${config.projectUrl}$suffix")
        }
        require(result.scheme == project.scheme && result.authority == project.authority) {
            "Storage returned a signed URL outside the configured project"
        }
        return result.toString()
    }

    private fun send(request: HttpRequest): HttpResponse<ByteArray> =
        http.send(request, HttpResponse.BodyHandlers.ofByteArray())

    private fun ensureSuccess(response: HttpResponse<ByteArray>, action: String) {
        if (response.statusCode() !in 200..299) throw IllegalStateException("$action (HTTP ${response.statusCode()})")
    }

    private fun requireValidObjectPath(path: String) {
        require(path.matches(Regex("^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}$"))) { "Evidence object path is invalid" }
    }
}

class EvidenceValidationException(message: String) : RuntimeException(message)

class EvidenceWorkflowService(private val repository: EvidenceRepository, private val storage: EvidenceObjectStorage) {
    fun createUpload(actorUserId: UUID, tenantId: UUID, mimeType: String, expectedSizeBytes: Long): EvidenceUploadGrant {
        validateDeclaration(mimeType, expectedSizeBytes)
        val evidenceId = UUID.randomUUID()
        val record = repository.createPending(actorUserId, tenantId, evidenceId, mimeType, expectedSizeBytes)
        val signedUrl = storage.createSignedUploadUrl(record.objectPath)
        return EvidenceUploadGrant(record.id.toString(), record.bucketId, record.objectPath, signedUrl, "PUT")
    }

    fun complete(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): Boolean {
        val pending = repository.findPending(actorUserId, tenantId, evidenceId) ?: return false
        val bytes = storage.downloadObject(pending.objectPath)
        if (bytes.size.toLong() != pending.expectedSizeBytes) throw EvidenceValidationException("Uploaded evidence size does not match its declaration")
        val detectedMime = detectMimeType(bytes)
        if (detectedMime != pending.mimeType) throw EvidenceValidationException("Uploaded evidence content does not match its declared MIME type")
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return repository.complete(actorUserId, tenantId, evidenceId, digest)
    }

    fun createDownloadUrl(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): EvidenceDownloadGrant? {
        val available = repository.findAvailable(actorUserId, tenantId, evidenceId) ?: return null
        return EvidenceDownloadGrant(
            available.record.id.toString(),
            storage.createSignedDownloadUrl(available.record.objectPath, 60),
            60
        )
    }

    private fun validateDeclaration(mimeType: String, size: Long) {
        if (mimeType !in ALLOWED_EVIDENCE_MIME_TYPES) throw EvidenceValidationException("Evidence MIME type is not allowed")
        if (size !in 1..MAX_EVIDENCE_BYTES) throw EvidenceValidationException("Evidence size must be between 1 byte and 10 MiB")
    }

    private fun detectMimeType(bytes: ByteArray): String {
        fun starts(vararg signature: Int): Boolean =
            bytes.size >= signature.size && signature.indices.all { (bytes[it].toInt() and 0xff) == signature[it] }

        return when {
            starts(0x25, 0x50, 0x44, 0x46, 0x2d) -> "application/pdf"
            starts(0xff, 0xd8, 0xff) -> "image/jpeg"
            starts(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a) -> "image/png"
            bytes.size >= 12 && String(bytes, 0, 4, StandardCharsets.US_ASCII) == "RIFF" &&
                String(bytes, 8, 4, StandardCharsets.US_ASCII) == "WEBP" -> "image/webp"
            else -> throw EvidenceValidationException("Uploaded evidence has an unsupported file signature")
        }
    }
}

@Serializable data class CreateEvidenceRequest(val mimeType: String, val sizeBytes: Long)
@Serializable data class EvidenceUploadGrant(
    val evidenceId: String, val bucket: String, val objectPath: String, val uploadUrl: String, val uploadMethod: String
)
@Serializable data class EvidenceCompleteResponse(val evidenceId: String, val status: String)
@Serializable data class EvidenceDownloadGrant(val evidenceId: String, val downloadUrl: String, val expiresInSeconds: Int)
