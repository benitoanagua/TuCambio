package com.tucambio

import java.sql.SQLException
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TenantAuthorizationTest {
    private val actor = UUID.fromString("10000000-0000-0000-0000-000000000001")
    private val tenant = UUID.fromString("20000000-0000-0000-0000-000000000001")
    private val membership = UUID.fromString("30000000-0000-0000-0000-000000000001")

    @Test
    fun activeMembershipReceivesOnlyAssignedCapabilities() {
        val service = TenantAuthorizationService(FakeRepository(
            TenantAccess(tenant, membership, setOf("operations.operate"))
        ))
        assertTrue(service.allows(actor, tenant, "operations.operate"))
        assertFalse(service.allows(actor, tenant, "rates.manage"))
    }

    @Test
    fun missingMembershipDeniesEveryCapability() {
        val service = TenantAuthorizationService(FakeRepository(null))
        assertNull(service.resolve(actor, tenant))
        assertFalse(service.allows(actor, tenant, "operations.operate"))
    }

    @Test
    fun invalidCapabilityCodeIsRejected() {
        val service = TenantAuthorizationService(FakeRepository(
            TenantAccess(tenant, membership, setOf("operations.operate"))
        ))
        kotlin.test.assertFailsWith<IllegalArgumentException> {
            service.allows(actor, tenant, "operations;operate")
        }
    }

    @Test
    fun databaseFailureDoesNotBecomeAnAuthorizationGrant() {
        val service = TenantAuthorizationService(object : TenantAccessRepository {
            override fun resolve(actorUserId: UUID, tenantId: UUID): TenantAccess? {
                throw SQLException("database unavailable")
            }
        })
        assertNotNull(kotlin.test.assertFailsWith<SQLException> {
            service.allows(actor, tenant, "operations.operate")
        })
    }

    private class FakeRepository(private val access: TenantAccess?) : TenantAccessRepository {
        override fun resolve(actorUserId: UUID, tenantId: UUID): TenantAccess? =
            access?.takeIf { it.tenantId == tenantId }
    }
}
