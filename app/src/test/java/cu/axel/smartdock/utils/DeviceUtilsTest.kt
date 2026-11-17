package cu.axel.smartdock.utils

import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceUtilsTest {
    private val own = "construction.ridgeline.smartdock/cu.axel.smartdock.services.DockService"
    private val upstream = "cu.axel.smartdock/cu.axel.smartdock.services.DockService"
    private val other = "example.other/example.other.AccessibilityService"

    @Test
    fun enablingAddsOnlyTheForkComponent() {
        assertEquals("$upstream:$other:$own", DeviceUtils.updateAccessibilityServices("$upstream:$other", own, true))
        assertEquals(own, DeviceUtils.updateAccessibilityServices("", own, true))
        assertEquals("$upstream:$own", DeviceUtils.updateAccessibilityServices("$upstream:$own", own, true))
    }

    @Test
    fun disablingPreservesTheOtherComponents() {
        assertEquals("$upstream:$other", DeviceUtils.updateAccessibilityServices("$upstream:$own:$other", own, false))
        assertEquals(upstream, DeviceUtils.updateAccessibilityServices(upstream, own, false))
        assertEquals("", DeviceUtils.updateAccessibilityServices(own, own, false))
    }
}
