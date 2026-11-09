package com.tucambio

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SupabaseEvidenceObjectStorageTest {
    private lateinit var server: HttpServer
    private lateinit var storage: SupabaseEvidenceObjectStorage
    private val serviceKey = "server-only-test-key"
    private val tenantId = UUID.fromString("71000000-0000-0000-0000-000000000001")
    private val evidenceId = UUID.fromString("72000000-0000-0000-0000-000000000001")
    private val objectPath = "$tenantId/$evidenceId"
    private val uploadAuthorization = AtomicReference<String?>()
    private val downloadAuthorization = AtomicReference<String?>()
    private val objectBytes = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)

    @BeforeTest
    fun startStorageStub() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/storage/v1/object/upload/sign/operation-evidence/$objectPath") { exchange ->
            uploadAuthorization.set(exchange.requestHeaders.getFirst("Authorization"))
            val response = """{"signedURL":"/object/upload/sign/operation-evidence/$objectPath?token=upload-token"}"""
            val bytes = response.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.createContext("/storage/v1/object/operation-evidence/$objectPath") { exchange ->
            downloadAuthorization.set(exchange.requestHeaders.getFirst("Authorization"))
            exchange.sendResponseHeaders(200, objectBytes.size.toLong())
            exchange.responseBody.use { it.write(objectBytes) }
        }
        server.createContext("/storage/v1/object/sign/operation-evidence/$objectPath") { exchange ->
            val response = """{"signedURL":"/object/sign/operation-evidence/$objectPath?token=download-token"}"""
            val bytes = response.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        storage = SupabaseEvidenceObjectStorage(
            SupabaseStorageConfig("http://127.0.0.1:${server.address.port}", serviceKey)
        )
    }

    @AfterTest
    fun stopStorageStub() {
        server.stop(0)
    }

    @Test
    fun signedUploadUrlUsesServerOnlyCredentialAndExactObjectPath() {
        val url = storage.createSignedUploadUrl(objectPath)

        assertEquals("Bearer $serviceKey", uploadAuthorization.get())
        assertTrue(url.startsWith("http://127.0.0.1:${server.address.port}/storage/v1/object/upload/sign/"))
        assertTrue(url.contains("token=upload-token"))
    }

    @Test
    fun backendCanReadPendingObjectWithServerCredentialForVerification() {
        val bytes = storage.downloadObject(objectPath)

        assertEquals("Bearer $serviceKey", downloadAuthorization.get())
        assertContentEquals(objectBytes, bytes)
    }

    @Test
    fun signedDownloadUrlUsesShortLivedPathScopedUrl() {
        val url = storage.createSignedDownloadUrl(objectPath, 60)

        assertTrue(url.startsWith("http://127.0.0.1:${server.address.port}/storage/v1/object/sign/"))
        assertTrue(url.contains("token=download-token"))
    }

    @Test
    fun rejectsObjectPathsNotBuiltFromTwoUuidSegments() {
        kotlin.test.assertFailsWith<IllegalArgumentException> {
            storage.createSignedUploadUrl("../other-tenant/private-file")
        }
    }
}
