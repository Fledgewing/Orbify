// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.view.ViewGroup

/** Presentation calls only the Library service. No account data or filesystem on paint. */
class LocalReadingSettingsActivity : SettingsPage() {
    private var snapshot: Map<String,Any?>? = null
    private var editing = false
    private var input: EditText? = null
    private var notice: String? = null
    private var generation = 0
    override fun onResume() { super.onResume(); load() }
    override fun onPause() { generation++; super.onPause() }
    private fun load() = call("reading.local.read",emptyMap<Any,Any>())
    private fun call(op: String, args: Map<*,*>) {
        val ticket=++generation
        LibraryLocalReading.command(op,args) { value,error -> Handler(Looper.getMainLooper()).post {
            if (ticket!=generation || isFinishing || isDestroyed) return@post
            notice=if(error=="invalid") "Enter a number from 1 to 999." else if(error!=null) "Not available · try again" else null
            if(error==null) {
                input?.let { (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(it.windowToken,0) }
                snapshot=value;editing=false
            }
            render()
        } }
    }
    override fun render() {
        val root=page(scroll=true)
        root.addView(Ui.header(this,if(editing) "Local reading goal" else "Reading statistics","‹ Back") {
            if(editing) { editing=false;render() } else finish()
        })
        lockedBar(root)
        val data=snapshot
        if(editing && !locked) {
            root.addView(Ui.text(this, data?.get("year").toString(), CompanionStyle.FORM_YEAR, bold = true).apply {
                typeface = CompanionStyle.serif
                setPadding(0, Ui.dp(this@LocalReadingSettingsActivity, 18), 0, Ui.dp(this@LocalReadingSettingsActivity, 20))
            })
            root.addView(Ui.text(this, "Books to finish on this reader", CompanionStyle.FORM_BODY))
            val typed=input?.text?.toString()
            input=Ui.input(this).apply {
                inputType=InputType.TYPE_CLASS_NUMBER
                setSingleLine()
                hint=""
                setText(typed ?: data?.get("target")?.toString().orEmpty())
                textSize = CompanionStyle.textSize(this@LocalReadingSettingsActivity, CompanionStyle.FORM_BODY)
                typeface = CompanionStyle.sans
                minHeight = Ui.dp(this@LocalReadingSettingsActivity, CompanionStyle.FORM_TARGET)
                background = Ui.box(this@LocalReadingSettingsActivity, Ui.PAPER, radiusDp = 0)
                val pad = Ui.dp(this@LocalReadingSettingsActivity, 12)
                setPadding(pad, pad, pad, pad)
                tag="local-goal-target"
            }
            root.addView(input, LinearLayout.LayoutParams(Ui.dp(this, CompanionStyle.FORM_FIELD_WIDTH), ViewGroup.LayoutParams.WRAP_CONTENT))
            root.addView(Ui.text(this, "1–999 books. This reader only. Your account goal stays separate.", CompanionStyle.FORM_CAPTION, color = Ui.MID).apply { setPadding(0, Ui.dp(this@LocalReadingSettingsActivity, 12), 0, Ui.dp(this@LocalReadingSettingsActivity, 16)) })
            notice?.let { root.addView(note(it)) }
            root.addView(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(Ui.button(this@LocalReadingSettingsActivity, "Off", heightDp = CompanionStyle.FORM_TARGET, sp = CompanionStyle.FORM_ACTION, radiusDp = CompanionStyle.FORM_RADIUS) {
                    input=null;call("reading.local.goal",emptyMap<Any,Any>())
                })
                addView(Ui.button(this@LocalReadingSettingsActivity, "Save", heightDp = CompanionStyle.FORM_TARGET, sp = CompanionStyle.FORM_ACTION, radiusDp = CompanionStyle.FORM_RADIUS) {
                    call("reading.local.goal",mapOf("target" to input!!.text.toString()))
                }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginStart = Ui.dp(this@LocalReadingSettingsActivity, 8) })
            })
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            input!!.requestFocus()
            input!!.post { (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(input,InputMethodManager.SHOW_IMPLICIT) }
        } else {
            input=null
            root.addView(Ui.row(this,"Local reading goal",data?.get("goal_label")?.toString()?.let(LuaValue::utf8) ?: "Loading…",onClick=if(locked || data==null) null else ({editing=true;render()})))
            root.addView(Ui.row(this,"Finished this year",data?.get("count_label")?.toString()?.let(LuaValue::utf8) ?: "Loading…"))
            root.addView(Ui.text(this, "Only books explicitly marked finished count.\nAccount totals remain separate when overlap is unknown.", CompanionStyle.FORM_CAPTION, color = Ui.MID))
            notice?.let { root.addView(note(it)) }
        }
    }
}
