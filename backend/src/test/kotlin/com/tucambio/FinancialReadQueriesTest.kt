package com.tucambio

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class FinancialReadQueriesTest {
    private val actor = UUID.fromString("10000000-0000-0000-0000-000000000001")
    private val tenant = UUID.fromString("20000000-0000-0000-0000-000000000001")
    private val repository = CapturingReadRepository()
    private val service = FinancialReadService(repository)

    @Test
    fun operationsPassTenantActorFilterAndPaginationToRepository() {
        val result = service.operations(actor, tenant, "PENDIENTE", 40, 80)

        assertEquals(repository.response, result)
        assertEquals(actor, repository.actorId)
        assertEquals(tenant, repository.tenantId)
        assertEquals("PENDIENTE", repository.status)
        assertEquals(40, repository.pageSize)
        assertEquals(80, repository.offset)
    }

    @Test
    fun movementsUseTheirDedicatedReadQuery() {
        service.movements(actor, tenant, null, 25, 0)

        assertEquals("movements", repository.lastQuery)
        assertEquals(null, repository.status)
    }

    @Test
    fun rejectsInvalidPaginationBeforeCallingRepository() {
        assertFailsWith<FinancialReadValidationException> {
            service.operations(actor, tenant, null, 101, 0)
        }
        assertFailsWith<FinancialReadValidationException> {
            service.movements(actor, tenant, null, 25, 10001)
        }
        assertEquals(null, repository.lastQuery)
    }

    @Test
    fun rejectsBlankOrOversizedStatus() {
        assertFailsWith<FinancialReadValidationException> {
            service.operations(actor, tenant, " ", 25, 0)
        }
        assertFailsWith<FinancialReadValidationException> {
            service.movements(actor, tenant, "x".repeat(65), 25, 0)
        }
    }

    private class CapturingReadRepository : FinancialReadRepository {
        val response = buildJsonObject { put("total", 0) }
        var actorId: UUID? = null
        var tenantId: UUID? = null
        var status: String? = null
        var pageSize: Int? = null
        var offset: Int? = null
        var lastQuery: String? = null

        private fun capture(
            query: String, actor: UUID, tenant: UUID, filter: String?, size: Int, start: Int
        ): JsonObject {
            lastQuery = query
            actorId = actor
            tenantId = tenant
            status = filter
            pageSize = size
            offset = start
            return response
        }

        override fun queryOperations(actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int) =
            capture("operations", actorId, tenantId, status, pageSize, offset)

        override fun queryMovements(actorId: UUID, tenantId: UUID, status: String?, pageSize: Int, offset: Int) =
            capture("movements", actorId, tenantId, status, pageSize, offset)
    }
}
