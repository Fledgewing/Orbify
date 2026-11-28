-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Fledgewing. Part of BookSync (see android/koreader/LICENSE).
-- Part of orbit.koplugin: loaded by main.lua into the plugin's shared environment, in the
-- order main.lua lists (docs/design/orbit-plugin.md "Module layout").

-- JNI: the companion's caller-checked call, package signers, explicit broadcasts, activities,
-- screen state, VPN state, launch extras
-- Built on KOReader's own JNI bridge (android-luajit-launcher assets/android.lua:1400-1416,
-- JNI:context, with the raw JNIEnv). Every Java call is checked for a pending exception,
-- because calling on with one pending aborts the VM.
---------------------------------------------------------------------------------------------

Jni = {}

-- Native activity state, independent of which reader/Home/settings owner received
-- the last Resume broadcast. The launcher helper only reads its lifecycle scalar.
function Jni.isResumed()
    if has_android and type(android.isResumed)=="function" then return android.isResumed() end
end

FLAG_INCLUDE_STOPPED_PACKAGES = 0x00000020
FLAG_RECEIVER_FOREGROUND = 0x10000000
FLAG_ACTIVITY_NEW_TASK = 0x10000000
TRANSPORT_VPN = 4

function int32(n) return ffi.new("int32_t", n) end

function check(env, what)
    if env[0].ExceptionCheck(env) ~= 0 then
        env[0].ExceptionClear(env)
        error("java exception in " .. what, 0)
    end
end

function del(env, obj)
    if obj ~= nil then env[0].DeleteLocalRef(env, obj) end
end

function methodId(env, obj, name, sig)
    local cls = env[0].GetObjectClass(env, obj)
    local id = env[0].GetMethodID(env, cls, name, sig)
    del(env, cls)
    if id == nil then
        env[0].ExceptionClear(env)
        error("no method " .. name .. sig, 0)
    end
    return id
end

function callObject(env, obj, name, sig, ...)
    local r = env[0].CallObjectMethod(env, obj, methodId(env, obj, name, sig), ...)
    check(env, name)
    return r
end

function callVoid(env, obj, name, sig, ...)
    env[0].CallVoidMethod(env, obj, methodId(env, obj, name, sig), ...)
    check(env, name)
end

function callBool(env, obj, name, sig, ...)
    local r = env[0].CallBooleanMethod(env, obj, methodId(env, obj, name, sig), ...)
    check(env, name)
    return r ~= 0
end

function callInt(env, obj, name, sig, ...)
    local r = env[0].CallIntMethod(env, obj, methodId(env, obj, name, sig), ...)
    check(env, name)
    return tonumber(r)
end

function withEnv(what, fn)
    if not has_android or not android.app then return nil, "no android bridge" end
    -- Results travel through upvalues: JNI:context returns unpack({...}), which drops
    -- values after a leading nil.
    local ra, rb, err
    local ok, ctx_err = pcall(android.jni.context, android.jni, android.app.activity.vm, function(jni)
        local env = jni.env
        local ok_inner, a, b = pcall(fn, env, android.app.activity.clazz, jni)
        if env[0].ExceptionCheck(env) ~= 0 then
            env[0].ExceptionClear(env)
            if ok_inner then ok_inner, a = false, "java exception" end
        end
        if ok_inner then ra, rb = a, b else err = a end
    end)
    if not ok then err = ctx_err end
    if err ~= nil then
        log(what, "failed:", tostring(err))
        return nil, err
    end
    return ra, rb
end

-- spec: { action, package?, class?, extras = { k = "string" }, flags? }
function newIntent(env, spec)
    local cls = env[0].FindClass(env, "android/content/Intent")
    check(env, "FindClass Intent")
    local ctor = env[0].GetMethodID(env, cls, "<init>", "(Ljava/lang/String;)V")
    check(env, "Intent.<init>")
    local jaction = env[0].NewStringUTF(env, spec.action)
    local intent = env[0].NewObject(env, cls, ctor, jaction)
    check(env, "new Intent")
    del(env, jaction)
    del(env, cls)
    if spec.class then
        local p = env[0].NewStringUTF(env, spec.package)
        local c = env[0].NewStringUTF(env, spec.class)
        del(env, callObject(env, intent, "setClassName",
            "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;", p, c))
        del(env, p); del(env, c)
    elseif spec.package then
        local p = env[0].NewStringUTF(env, spec.package)
        del(env, callObject(env, intent, "setPackage", "(Ljava/lang/String;)Landroid/content/Intent;", p))
        del(env, p)
    end
    for k, v in pairs(spec.extras or {}) do
        local jk = env[0].NewStringUTF(env, k)
        local jv = env[0].NewStringUTF(env, tostring(v))
        del(env, callObject(env, intent, "putExtra",
            "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;", jk, jv))
        del(env, jk); del(env, jv)
    end
    if spec.flags then
        del(env, callObject(env, intent, "addFlags", "(I)Landroid/content/Intent;", int32(spec.flags)))
    end
    return intent
end

function Jni.sendBroadcast(spec)
    spec.flags = (spec.flags or 0) + FLAG_INCLUDE_STOPPED_PACKAGES + FLAG_RECEIVER_FOREGROUND
    return withEnv("broadcast " .. spec.action, function(env, activity)
        local intent = newIntent(env, spec)
        callVoid(env, activity, "sendBroadcast", "(Landroid/content/Intent;)V", intent)
        del(env, intent)
        return true
    end)
end

-- A new android.os.Bundle with string extras.
function newBundle(env, extras)
    local cls = env[0].FindClass(env, "android/os/Bundle")
    check(env, "FindClass Bundle")
    local ctor = env[0].GetMethodID(env, cls, "<init>", "()V")
    check(env, "Bundle.<init>")
    local b = env[0].NewObject(env, cls, ctor)
    check(env, "new Bundle")
    del(env, cls)
    for k, v in pairs(extras or {}) do
        local jk = env[0].NewStringUTF(env, k)
        local jv = env[0].NewStringUTF(env, tostring(v))
        callVoid(env, b, "putString", "(Ljava/lang/String;Ljava/lang/String;)V", jk, jv)
        del(env, jk); del(env, jv)
    end
    return b
end

function bundleString(env, jni, b, key)
    local jk = env[0].NewStringUTF(env, key)
    local jv = callObject(env, b, "getString", "(Ljava/lang/String;)Ljava/lang/String;", jk)
    del(env, jk)
    if jv == nil then return nil end
    local v = jni:to_string(jv)
    del(env, jv)
    return v
end

-- What a call's answer may carry (android/docs/INTERFACE.md).
CALL_ANSWER = { "ok", "why", "status", "key", "proof", "id", "body", "owner", "pending" }

-- ContentResolver.call(content://<authority>, method, null, extras) (android/docs/INTERFACE.md):
-- the companion checks who called before it acts. Returns the answer's CALL_ANSWER fields
-- (strings), or nil and the error (no such provider, a Java exception).
function Jni.call(authority, method, extras)
    return withEnv("call " .. method, function(env, activity, jni)
        local cr = callObject(env, activity, "getContentResolver", "()Landroid/content/ContentResolver;")
        if cr == nil then error("no ContentResolver", 0) end
        local ucls = env[0].FindClass(env, "android/net/Uri")
        check(env, "FindClass Uri")
        local parse = env[0].GetStaticMethodID(env, ucls, "parse", "(Ljava/lang/String;)Landroid/net/Uri;")
        check(env, "Uri.parse")
        local js = env[0].NewStringUTF(env, "content://" .. authority)
        local uri = env[0].CallStaticObjectMethod(env, ucls, parse, js)
        check(env, "Uri.parse()")
        del(env, js); del(env, ucls)
        local b = newBundle(env, extras)
        local jm = env[0].NewStringUTF(env, method)
        local r = callObject(env, cr, "call",
            "(Landroid/net/Uri;Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;", uri, jm, nil, b)
        del(env, jm); del(env, b); del(env, uri); del(env, cr)
        if r == nil then return { ok = "0", why = "no answer" } end
        local out = {}
        for _, k in ipairs(CALL_ANSWER) do out[k] = bundleString(env, jni, r, k) end
        del(env, r)
        return out
    end)
end

-- The SHA-256 of each certificate that signs pkg ("AB:CD:…", upper case), as PackageManager
-- reports it (signingInfo on Android 9+, else signatures). {} when it isn't installed; nil
-- when it can't be read.
GET_SIGNING_CERTIFICATES = 0x08000000
GET_SIGNATURES = 0x40

function certHex(env, jni, sig)
    local bytes = callObject(env, sig, "toByteArray", "()[B")
    local mcls = env[0].FindClass(env, "java/security/MessageDigest")
    check(env, "FindClass MessageDigest")
    local gi = env[0].GetStaticMethodID(env, mcls, "getInstance", "(Ljava/lang/String;)Ljava/security/MessageDigest;")
    check(env, "MessageDigest.getInstance")
    local alg = env[0].NewStringUTF(env, "SHA-256")
    local md = env[0].CallStaticObjectMethod(env, mcls, gi, alg)
    check(env, "MessageDigest.getInstance()")
    del(env, alg); del(env, mcls)
    local digest = callObject(env, md, "digest", "([B)[B", bytes)
    local bcls = env[0].FindClass(env, "java/math/BigInteger")
    check(env, "FindClass BigInteger")
    local ctor = env[0].GetMethodID(env, bcls, "<init>", "(I[B)V")
    check(env, "BigInteger.<init>")
    local big = env[0].NewObject(env, bcls, ctor, int32(1), digest)
    check(env, "new BigInteger")
    local js = callObject(env, big, "toString", "(I)Ljava/lang/String;", int32(16))
    local hex = jni:to_string(js)
    del(env, js); del(env, big); del(env, bcls); del(env, digest); del(env, md); del(env, bytes)
    return Companion.fingerprint(hex)
end

function Jni.packageSigners(pkg)
    return withEnv("signers " .. pkg, function(env, activity, jni)
        local pm = callObject(env, activity, "getPackageManager", "()Landroid/content/pm/PackageManager;")
        if pm == nil then error("no PackageManager", 0) end
        local jp = env[0].NewStringUTF(env, pkg)
        local sigs
        local okn, pi = pcall(callObject, env, pm, "getPackageInfo", "(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;", jp, int32(GET_SIGNING_CERTIFICATES))
        if okn and pi ~= nil then
            local pcls = env[0].GetObjectClass(env, pi)
            local fid = env[0].GetFieldID(env, pcls, "signingInfo", "Landroid/content/pm/SigningInfo;")
            if env[0].ExceptionCheck(env) ~= 0 then env[0].ExceptionClear(env); fid = nil end
            del(env, pcls)
            local si = fid ~= nil and env[0].GetObjectField(env, pi, fid) or nil
            if si ~= nil then
                local multi = callBool(env, si, "hasMultipleSigners", "()Z")
                sigs = callObject(env, si, multi and "getApkContentsSigners" or "getSigningCertificateHistory", "()[Landroid/content/pm/Signature;")
                del(env, si)
            end
            del(env, pi)
        end
        if sigs == nil then
            local oko, old = pcall(callObject, env, pm, "getPackageInfo", "(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;", jp, int32(GET_SIGNATURES))
            if not oko or old == nil then del(env, jp); del(env, pm); return {} end
            local pcls = env[0].GetObjectClass(env, old)
            local fid = env[0].GetFieldID(env, pcls, "signatures", "[Landroid/content/pm/Signature;")
            check(env, "PackageInfo.signatures")
            del(env, pcls)
            sigs = env[0].GetObjectField(env, old, fid)
            del(env, old)
        end
        del(env, jp); del(env, pm)
        local out = {}
        if sigs ~= nil then
            for i = 0, env[0].GetArrayLength(env, sigs) - 1 do
                local sig = env[0].GetObjectArrayElement(env, sigs, i)
                check(env, "GetObjectArrayElement")
                table.insert(out, certHex(env, jni, sig))
                del(env, sig)
            end
            del(env, sigs)
        end
        return out
    end)
end

function Jni.startActivity(spec)
    spec.flags = (spec.flags or 0) + FLAG_ACTIVITY_NEW_TASK
    return withEnv("startActivity " .. spec.action, function(env, activity)
        local intent = newIntent(env, spec)
        callVoid(env, activity, "startActivity", "(Landroid/content/Intent;)V", intent)
        del(env, intent)
        return true
    end)
end

function systemService(env, activity, name)
    local jname = env[0].NewStringUTF(env, name)
    local svc = callObject(env, activity, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;", jname)
    del(env, jname)
    return svc
end

-- PowerManager.isInteractive(): false once the screen is off. nil if unknown.
function Jni.isInteractive()
    return withEnv("isInteractive", function(env, activity)
        local pm = systemService(env, activity, "power")
        if pm == nil then error("no PowerManager", 0) end
        local on = callBool(env, pm, "isInteractive", "()Z")
        del(env, pm)
        return on
    end)
end

-- WifiManager.isWifiEnabled(): the radio, not the connection. nil if unknown.
-- KOReader's Android backend only knows "connected" (device.lua:335-341, isWifiOn = isConnected).
-- Wi-Fi radio on? true/false, nil if unknown. Not WifiManager.isWifiEnabled(): KOReader's
-- manifest has no ACCESS_WIFI_STATE (android-luajit-launcher app/src/main/AndroidManifest.xml:
-- INTERNET, ACCESS_NETWORK_STATE, ...), so that call throws SecurityException. Settings.Global
-- "wifi_on" (Settings.Global.WIFI_ON) needs no permission: 1 on, 2 on in airplane mode, 0 off,
-- 3 off by airplane mode.
function Jni.wifiEnabled()
    return withEnv("wifi_on", function(env, activity)
        local cr = callObject(env, activity, "getContentResolver", "()Landroid/content/ContentResolver;")
        if cr == nil then error("no ContentResolver", 0) end
        local cls = env[0].FindClass(env, "android/provider/Settings$Global")
        check(env, "FindClass Settings$Global")
        local mid = env[0].GetStaticMethodID(env, cls, "getInt", "(Landroid/content/ContentResolver;Ljava/lang/String;I)I")
        check(env, "Settings.Global.getInt")
        local key = env[0].NewStringUTF(env, "wifi_on")
        local v = tonumber(env[0].CallStaticIntMethod(env, cls, mid, cr, key, int32(-1)))
        check(env, "Settings.Global.getInt wifi_on")
        del(env, key)
        del(env, cls)
        del(env, cr)
        return Plan.wifiOnSetting(v)
    end)
end

-- PackageManager.getApplicationEnabledSetting(pkg): 0 default, 1 enabled, 2/3/4 disabled.
-- nil when the package isn't installed (it throws IllegalArgumentException).
function Jni.appEnabledSetting(pkg)
    return withEnv("getApplicationEnabledSetting " .. pkg, function(env, activity)
        local pm = callObject(env, activity, "getPackageManager", "()Landroid/content/pm/PackageManager;")
        if pm == nil then error("no PackageManager", 0) end
        local jp = env[0].NewStringUTF(env, pkg)
        local okc, v = pcall(callInt, env, pm, "getApplicationEnabledSetting", "(Ljava/lang/String;)I", jp)
        del(env, jp)
        del(env, pm)
        if not okc then return false end -- missing: false, so withEnv doesn't log it as a failure
        return v
    end)
end

-- Whether any network has the VPN transport (Tailscale up). nil if unknown.
function Jni.vpnActive()
    return withEnv("vpnActive", function(env, activity)
        local cm = systemService(env, activity, "connectivity")
        if cm == nil then error("no ConnectivityManager", 0) end
        local nets = callObject(env, cm, "getAllNetworks", "()[Landroid/net/Network;")
        local found = false
        if nets ~= nil then
            local n = env[0].GetArrayLength(env, nets)
            for i = 0, n - 1 do
                local net = env[0].GetObjectArrayElement(env, nets, i)
                check(env, "GetObjectArrayElement")
                local caps = callObject(env, cm, "getNetworkCapabilities",
                    "(Landroid/net/Network;)Landroid/net/NetworkCapabilities;", net)
                if caps ~= nil then
                    if callBool(env, caps, "hasTransport", "(I)Z", int32(TRANSPORT_VPN)) then found = true end
                    del(env, caps)
                end
                del(env, net)
                if found then break end
            end
            del(env, nets)
        end
        del(env, cm)
        return found
    end)
end

-- Reads and removes a string extra from the activity's current intent (the launch intent,
-- or the latest one: MainActivity.onNewIntent calls setIntent, android-luajit-launcher
-- MainActivity.kt:205-210).
-- An app's label ("Meebook Launcher"), also when it's disabled; false when missing.
function Jni.appLabel(pkg)
    return withEnv("appLabel " .. pkg, function(env, activity, jni)
        local pm = callObject(env, activity, "getPackageManager", "()Landroid/content/pm/PackageManager;")
        if pm == nil then error("no PackageManager", 0) end
        local jp = env[0].NewStringUTF(env, pkg)
        local label = false
        local oka, ai = pcall(callObject, env, pm, "getApplicationInfo", "(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;", jp, 0x200)
        if oka and ai ~= nil then
            local okl, cs = pcall(callObject, env, pm, "getApplicationLabel", "(Landroid/content/pm/ApplicationInfo;)Ljava/lang/CharSequence;", ai)
            if okl and cs ~= nil then
                local okt, js = pcall(callObject, env, cs, "toString", "()Ljava/lang/String;")
                if okt and js ~= nil then label = jni:to_string(js); del(env, js) end
                del(env, cs)
            end
            del(env, ai)
        end
        del(env, jp)
        del(env, pm)
        return label
    end)
end

function Jni.takeIntentExtra(key)
    return withEnv("takeIntentExtra", function(env, activity, jni)
        local intent = callObject(env, activity, "getIntent", "()Landroid/content/Intent;")
        if intent == nil then return false end
        local jk = env[0].NewStringUTF(env, key)
        local jv = callObject(env, intent, "getStringExtra", "(Ljava/lang/String;)Ljava/lang/String;", jk)
        local value = false
        if jv ~= nil then
            value = jni:to_string(jv)
            del(env, jv)
            callVoid(env, intent, "removeExtra", "(Ljava/lang/String;)V", jk)
        end
        del(env, jk)
        del(env, intent)
        return value
    end)
end

---------------------------------------------------------------------------------------------
