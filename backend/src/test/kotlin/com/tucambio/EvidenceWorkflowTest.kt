package com.tucambio

import java.security.MessageDigest
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

class EvidenceWorkflowTest {
    private val actor = UUID.fromString("61000000-0000-0000-0000-000000000001")
    private val tenant = UUID.fromString("62000000-0000-0000-0000-000000000001")
    private val evidenceId = UUID.fromString("63000000-0000-0000-0000-000000000001")
    private val record = EvidenceRecord(
        evidenceId,
        "operation-evidence",
        "$tenant/$evidenceId",
        "image/png",
        8
    )

    @Test
    fun uploadGrantUsesBackendCreatedPathAndActorToken() {
        val repository = FakeEvidenceRepository(record)
        val storage = FakeEvidenceStorage()
        val service = EvidenceWorkflowService(repository, storage)

        val grant = service.createUpload(actor, tenant, "image/png", 8, "validated-user-jwt")

        assertTrue(runCatching { UUID.fromString(grant.evidenceId) }.isSuccess)
        assertEquals(repository.lastCreatedId.toString(), grant.evidenceId)
        assertEquals("operation-evidence", grant.bucket)
        assertEquals("$tenant/${grant.evidenceId}", grant.objectPath)
        assertEquals("PUT", grant.uploadMethod)
        assertEquals("https://storage.example/upload/signed", grant.uploadUrl)
        assertEquals(record.objectPath, storage.lastSignedUploadPath)
        assertEquals("validated-user-jwt", storage.lastActorToken)
    }

    @Test
    fun declarationRejectsUnsupportedMimeAndOversizedFilesBeforeCreatingMetadata() {
        val repository = FakeEvidenceRepository(record)
        val service = EvidenceWorkflowService(repository, FakeEvidenceStorage())

        assertFailsWith<EvidenceValidationException> {
            service.createUpload(actor, tenant, "text/plain", 8, "jwt")
        }
        assertFailsWith<EvidenceValidationException> {
            service.createUpload(actor, tenant, "image/png", 10L * 1024 * 1024 + 1, "jwt")
        }
        assertEquals(0, repository.createdCount)
    }

    @Test
    fun completionVerifiesActualBytesAndPersistsSha256() {
        val bytes = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
        val repository = FakeEvidenceRepository(record)
        val storage = FakeEvidenceStorage(downloadedBytes = bytes)
        val service = EvidenceWorkflowService(repository, storage)

        assertTrue(service.complete(actor, tenant, evidenceId))
        assertContentEquals(MessageDigest.getInstance("SHA-256").digest(bytes), repository.completedSha256)
        assertEquals(record.objectPath, storage.lastDownloadedPath)
    }

    @Test
    fun completionRejectsMimeMismatchAndDoesNotMarkEvidenceAvailable() {
        val bytes = "%PDF-1.7".toByteArray()
        val repository = FakeEvidenceRepository(record.copy(expectedSizeBytes = bytes.size.toLong()))
        val storage = FakeEvidenceStorage(downloadedBytes = bytes)
        val service = EvidenceWorkflowService(repository, storage)

        assertFailsWith<EvidenceValidationException> { service.complete(actor, tenant, evidenceId) }
        assertFalse(repository.wasCompleted)
    }

    @Test
    fun completionRejectsDeclaredSizeMismatch() {
        val bytes = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
        val repository = FakeEvidenceRepository(record.copy(expectedSizeBytes = 9))
        val service = EvidenceWorkflowService(repository, FakeEvidenceStorage(downloadedBytes = bytes))

        assertFailsWith<EvidenceValidationException> { service.complete(actor, tenant, evidenceId) }
        assertFalse(repository.wasCompleted)
    }

    @Test
    fun downloadUrlIsIssuedOnlyForRepositoryAuthorizedAvailableEvidence() {
        val repository = FakeEvidenceRepository(record, available = true)
        val storage = FakeEvidenceStorage()
        val service = EvidenceWorkflowService(repository, storage)

        val grant = service.createDownloadUrl(actor, tenant, evidenceId)
        assertEquals(evidenceId.toString(), grant?.evidenceId)
        assertEquals(60, grant?.expiresInSeconds)
        assertEquals("https://storage.example/download/signed", grant?.downloadUrl)
        assertEquals(record.objectPath, storage.lastSignedDownloadPath)

        val denied = EvidenceWorkflowService(FakeEvidenceRepository(record, available = false), storage)
            .createDownloadUrl(actor, tenant, evidenceId)
        assertNull(denied)
    }

    private class FakeEvidenceRepository(
        private val record: EvidenceRecord,
        private val available: Boolean = false
    ) : EvidenceRepository {
        var createdCount = 0
        var lastCreatedId: UUID? = null
        var wasCompleted = false
        var completedSha256: ByteArray? = null

        override fun createPending(
            actorUserId: UUID,
            tenantId: UUID,
            evidenceId: UUID,
            mimeType: String,
            expectedSizeBytes: Long
        ): EvidenceRecord {
            createdCount++
            lastCreatedId = evidenceId
            return record.copy(
                id = evidenceId,
                objectPath = "$tenantId/$evidenceId",
                mimeType = mimeType,
                expectedSizeBytes = expectedSizeBytes
            )
        }

        override fun findPending(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): EvidenceRecord? = record

        override fun complete(actorUserId: UUID, tenantId: UUID, evidenceId: UUID, sha256: ByteArray): Boolean {
            wasCompleted = true
            completedSha256 = sha256
            return true
        }

        override fun findAvailable(actorUserId: UUID, tenantId: UUID, evidenceId: UUID): AvailableEvidence? =
            if (available) AvailableEvidence(record, ByteArray(32)) else null
    }

    private class FakeEvidenceStorage(
        private val downloadedBytes: ByteArray = byteArrayOf()
    ) : EvidenceObjectStorage {
        var lastSignedUploadPath: String? = null
        var lastActorToken: String? = null
        var lastDownloadedPath: String? = null
        var lastSignedDownloadPath: String? = null

        override fun createSignedUploadUrl(objectPath: String, actorAccessToken: String): String {
            lastSignedUploadPath = objectPath
            lastActorToken = actorAccessToken
            return "https://storage.example/upload/signed"
        }

        override fun downloadObject(objectPath: String): ByteArray {
            lastDownloadedPath = objectPath
            return downloadedBytes
        }

        override fun createSignedDownloadUrl(objectPath: String, expiresInSeconds: Int): String {
            lastSignedDownloadPath = objectPath
            return "https://storage.example/download/signed"
        }
    }
}
