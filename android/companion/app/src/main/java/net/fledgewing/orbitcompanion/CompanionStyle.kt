// SPDX-License-Identifier: MIT
package net.fledgewing.orbitcompanion

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.view.View
import android.widget.LinearLayout

/** Shared native surface tokens. Companion checklist uses the approved system sans family;
 * serif is reserved for the diagnostic heading, as in crash-summary-mockups.html. */
object CompanionStyle {
    const val TITLE = 34f
    const val LABEL = 36f
    const val BODY = 30f
    const val CAPTION = 24f
    const val ACTION = 28f
    const val CONTROL = 28f
    const val MIN_BODY = 24f
    // Shared readable roles: never reduce a screen's type to make it fit.
    const val FORM_BODY = 36f
    const val FORM_CAPTION = 30f
    const val FORM_ACTION = 37f
    const val FORM_YEAR = 52f
    const val FORM_HEADING = 48f
    const val FORM_TARGET = 96
    const val FORM_FIELD_WIDTH = 120
    const val FORM_BUTTON_INSET = 24
    const val HERO_TYPE = 38f
    const val HERO_HEIGHT = 270
    const val TILE_HEIGHT = 160
    const val TILE_TYPE = 24f
    const val TILE_ICON = 64
    const val STATUS_TYPE = 28f
    const val STATUS_CAPTION = 24f
    const val SUMMARY_TYPE = 31f
    /** One floor for every Activity; smaller readers scroll rather than get a special scale. */
    fun textSize(ctx: Context, sp: Float): Float {
        val width = ctx.resources.displayMetrics.widthPixels / ctx.resources.displayMetrics.density
        return maxOf(sp, MIN_BODY) * (width / 749f).coerceIn(0.75f, 1.5f)
    }
    fun subtitleScale(parentSp: Float): Float = maxOf(0.65f, MIN_BODY / parentSp)

    const val PAGE_INSET = 25
    const val CARD_RADIUS = 10
    const val FORM_RADIUS = 0
    const val CARD_INSET = 20
    val sans: Typeface = Typeface.create("sans-serif", Typeface.NORMAL)
    val strong: Typeface = Typeface.create("sans-serif", Typeface.BOLD)
    val serif: Typeface = Typeface.create("serif", Typeface.BOLD)

    /** Drawn paths rather than font-dependent emoji; the same line icons on every Android. */
    fun icon(ctx: Context, key: String): View = object : View(ctx) {
        private val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Ui.INK; style = Paint.Style.STROKE; strokeWidth = 1.8f
            strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        override fun onDraw(c: Canvas) {
            super.onDraw(c)
            c.save(); c.translate(width * .25f, height * .25f); c.scale(width / 48f, height / 48f)
            fun line(vararg xy: Float) {
                val p = Path(); p.moveTo(xy[0], xy[1])
                for (i in 2 until xy.size step 2) p.lineTo(xy[i], xy[i + 1])
                c.drawPath(p, ink)
            }
            when (key) {
                "sync" -> { c.drawArc(3f, 4f, 21f, 20f, 200f, 260f, false, ink); line(3f, 4f, 3f, 10f, 9f, 10f); line(21f, 20f, 21f, 14f, 15f, 14f) }
                "library" -> { line(12f, 3f, 12f, 17f); line(7f, 12f, 12f, 17f, 17f, 12f); line(4f, 21f, 20f, 21f) }
                "reading" -> { line(3f, 20f, 9f, 4f, 15f, 20f); line(5f, 14f, 13f, 14f); c.drawCircle(19f, 16f, 3f, ink); line(22f, 13f, 22f, 20f) }
                "sleep" -> { val p = Path(); p.moveTo(15f, 3f); p.cubicTo(0f, 4f, 1f, 23f, 15f, 21f); p.cubicTo(19f, 21f, 22f, 18f, 22f, 16f); p.cubicTo(10f, 23f, 7f, 9f, 15f, 3f); c.drawPath(p, ink) }
                "updates" -> { c.drawRoundRect(3f, 3f, 21f, 21f, 3f, 3f, ink); line(12f, 17f, 12f, 7f); line(7f, 12f, 12f, 7f, 17f, 12f) }
                "server" -> { c.drawCircle(12f, 7f, 4f, ink); c.drawArc(4f, 13f, 20f, 28f, 180f, 180f, false, ink) }
                "kids" -> { c.drawRoundRect(5f, 10f, 19f, 22f, 2f, 2f, ink); c.drawArc(8f, 2f, 16f, 17f, 180f, 180f, false, ink) }
                "buttons" -> { c.drawRoundRect(5f, 2f, 19f, 22f, 4f, 4f, ink); c.drawCircle(12f, 9f, 2f, ink); line(10f, 16f, 14f, 16f) }
                "setup" -> { c.drawRoundRect(3f, 3f, 21f, 21f, 2f, 2f, ink); line(7f, 12f, 11f, 16f, 18f, 8f) }
                else -> { c.drawCircle(12f, 12f, 10f, ink); line(12f, 11f, 12f, 18f); c.drawCircle(12f, 7f, .6f, ink) }
            }
            c.restore()
        }
    }.apply {
        val size = Ui.dp(ctx, 44)
        layoutParams = LinearLayout.LayoutParams(size, size).apply { marginEnd = Ui.dp(ctx, 16) }
        background = Ui.box(ctx, 0xffededed.toInt(), strokeDp = 0, radiusDp = 12)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
}
