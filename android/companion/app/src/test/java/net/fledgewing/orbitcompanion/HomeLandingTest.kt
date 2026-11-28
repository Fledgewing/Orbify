// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.app.Application
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34])
class HomeLandingTest {
    private val app get() = RuntimeEnvironment.getApplication()
    private fun drain()=generateSequence { shadowOf(app).nextStartedActivity }.toList()
    @Before fun prepare() {
        SettingsStore.useSchema(SettingsSchema.parse(File("../../../shared/settings/schema.json").readText()))
        Prefs(app).mode=OrbitMode.FULL
        Prefs(app).homeApp=""
        Prefs(app).homeButton=HomeButton.LIBRARY
        Prefs(app).patchVersionSeen=BuildConfig.VERSION_NAME
        UpdateReturn.reset(app)
        EinkActivity.forgetPages()
        drain()
    }
    @Test fun appIconKeepsItsCompanionTaskRootInFullMode() {
        val launch=app.packageManager.getLaunchIntentForPackage(app.packageName)!!
        assertEquals(StatusActivity::class.java.name,launch.component!!.className)
        val controller=Robolectric.buildActivity(StatusActivity::class.java,launch).setup()
        val activity=controller.get()
        assertFalse(activity.isFinishing)
        assertTrue(EinkActivity.pageResumed())
        assertFalse(drain().any { it.component?.className==LauncherActivity::class.java.name || it.component?.packageName==Koreader.PKG })
        controller.pause().resume()
        assertFalse(activity.isFinishing)
        assertFalse(drain().any { it.component?.packageName==Koreader.PKG })
        controller.pause().stop().destroy()
    }
    @Test fun signedOutHomeDoesNotOpenASignInSetupPrompt() {
        assertTrue(Setup.checks(app).single {it.id=="signed_in"}.optional)
        val info=PackageInfo().apply {
            packageName=Koreader.PKG
            applicationInfo=ApplicationInfo().apply {packageName=Koreader.PKG;enabled=true}
            activities=arrayOf(ActivityInfo().apply {name="${Koreader.PKG}.MainActivity";packageName=Koreader.PKG;exported=true})
        }
        shadowOf(app.packageManager).installPackage(info)
        val controller=Robolectric.buildActivity(HomeActivity::class.java,Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)).setup()
        val starts=drain()
        assertFalse(starts.any {it.component?.className==AttentionActivity::class.java.name})
        assertTrue(starts.any {it.component?.packageName==Koreader.PKG})
        controller.pause().stop().destroy()
    }
}
