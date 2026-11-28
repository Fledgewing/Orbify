package net.fledgewing.orbitcompanion

import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.view.WindowManager

/** Plain Your server screen. No stored credential is read into an editable field. */
class AccountActivity : EinkActivity() {
    override val returnable = false
    override val pinGuarded = true
    private var busy = false
    private var message = ""
    private var selected: String? = null
    private var serverValue = ""
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        serverValue = intent.getStringExtra("server").orEmpty()
        LibraryAccount.initialize(this) { if (!isFinishing && !isDestroyed) render() }
    }
    override fun onResume() { super.onResume(); render() }
    override fun refresh() = render()
    private fun render() {
        val start = System.nanoTime()
        val root = page()
        root.addView(Ui.text(this, "Your server", 26f, bold = true))
        val state = LibraryAccount.state()
        require(LuaValue.encode(state).size <= 16384)
        val kind = selected
        val labels = mapOf("account" to "Server account", "sync" to "Sync login", "opds" to "OPDS login")
        if (kind == null) {
            for (id in listOf("account","sync","opds")) {
                val login = state[id] as? Map<*, *>
                val detail = if (login?.get("set") == true) if (login["origin"] == "account") "Set · from account" else "Set · entered by you" else "Not set"
                root.addView(Ui.row(this, labels.getValue(id), detail, onClick = { if (!busy) { selected = id; message = ""; render() } }))
            }
            root.addView(Ui.text(this, "Each login is optional. Signing out of the server account also removes logins it supplied. Logins you entered separately stay.", 18f))
        } else {
            root.addView(Ui.text(this, labels.getValue(kind), 22f, bold = true))
            fun field(hintText: String, initial: String, type: Int, max: Int) = Ui.input(this).apply {
                hint = hintText; setText(initial); inputType = type; filters = arrayOf(InputFilter.LengthFilter(max))
                isSaveEnabled = false; setSingleLine(true); root.addView(this)
            }
            val server = field("Server address", serverValue, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI, 2048)
            val user = field("Username", "", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS, 100)
            val secret = field(if (kind == "sync") "Password or sync key" else "Password", "", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD, 1024)
            val derived = Ui.checkBox(this, "This is the derived sync key").apply { isSaveEnabled = false }
            if (kind == "sync") root.addView(derived)
            root.addView(Ui.button(this, if (busy) "Saving…" else if (kind == "account") "Sign in" else "Save login", solid = true) {
                if (!busy) {
                    serverValue = server.text.toString(); val username = user.text.toString()
                    val password = CharArray(secret.length()) { secret.text[it] }; secret.text.clear()
                    val key = derived.isChecked
                    busy = true; render()
                    if (kind == "account") LibraryAccount.signIn(this,serverValue,username,password,::finished)
                    else LibraryAccount.setLogin(this,kind,serverValue,username,password,key,::finished)
                }
            })
            if (kind == "account") root.addView(Ui.text(this, "Password sign-in. Browser sign-in support follows later. Account sign-in fills only empty sync and OPDS logins.",18f))
            if ((state[kind] as? Map<*, *>)?.get("set") == true) root.addView(Ui.button(this, if (kind == "account") "Sign out" else "Remove login") {
                if (!busy) { busy = true; render(); if (kind == "account") LibraryAccount.signOut(this,::finished) else LibraryAccount.removeLogin(this,kind,::finished) }
            })
            if (kind != "account" && state["signedIn"] == true) root.addView(Ui.button(this,"Replace with account login") {
                if (!busy) { busy = true; render(); LibraryAccount.useAccountLogin(this,kind,::finished) }
            })
        }
        if (message.isNotEmpty()) root.addView(Ui.text(this,message,18f))
        root.addView(Ui.button(this,"Back") { if (selected != null) { selected = null; render() } else finish() })
        OLog.i("server.paint ms=${(System.nanoTime()-start)/1_000_000} rows=3 bytes=${LuaValue.encode(state).size} spawns=0 network=0")
    }
    private fun finished(error: String?) {
        if (isFinishing || isDestroyed) return
        busy = false
        message = when (error) { null -> ""; "unauthorized" -> "Check the login."; "forbidden" -> "Your server does not permit this operation."; "expired" -> "Session expired. Sign in again."; else -> "Could not save the login. Try again." }
        if (error == null) selected = null
        render()
    }
}
