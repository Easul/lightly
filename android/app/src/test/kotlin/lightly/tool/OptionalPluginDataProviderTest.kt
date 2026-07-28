package lightly.tool

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OptionalPluginDataProviderTest {
    @Test
    fun `only accepts the telegram config path`() {
        assertTrue(
            OptionalPluginDataProvider.isSupportedPath(
                OptionalPluginDataProvider.TELEGRAM_CONFIG_PATH,
            ),
        )
        assertFalse(OptionalPluginDataProvider.isSupportedPath("unsupported"))
        assertFalse(OptionalPluginDataProvider.isSupportedPath(null))
    }
}
