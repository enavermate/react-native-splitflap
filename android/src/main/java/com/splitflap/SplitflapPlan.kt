package com.splitflap

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.cbrt
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Plan v1, as src/planner/types.ts defines it and ios/SplitflapPlan.mm decodes it: the same fields,
 * the same defaults, unknown fields ignored.
 */
enum class SplitflapEasing {
  OUT,
  IN_OUT,
  LINEAR;

  /** Progress 0…1 at a normalized time. Must match src/planner/timeline.ts. */
  fun ease(x: Double): Double {
    val t = min(1.0, max(0.0, x))
    return when (this) {
      OUT -> 1 - (1 - t).pow(3)
      IN_OUT -> if (t < 0.5) 4 * t * t * t else 1 - (-2 * t + 2).pow(3) / 2
      LINEAR -> t
    }
  }

  /** Normalized time at which progress p is reached. */
  fun inverse(p: Double): Double {
    val q = min(1.0, max(0.0, p))
    return when (this) {
      OUT -> 1 - cbrt(1 - q)
      IN_OUT -> if (q < 0.5) cbrt(q / 4) else 1 - cbrt(2 * (1 - q)) / 2
      LINEAR -> q
    }
  }
}

class SplitflapCellPlan(
  val index: Int,
  val from: String,
  val to: String,
  val path: List<String>,
  val delayMs: Double,
  val durationMs: Double,
  val easing: SplitflapEasing,
  /** 1 = the old glyph leaves upward and the new one comes from below. */
  val dir: Int,
  val land: Int,
  val stepMs: Double,
  /** Scramble: the letters to flicker through, in the target's case (planner-supplied). */
  val letters: List<String>,
  val resumeK: Int?,
  val resumeF: Double,
) {
  fun glyphAt(i: Int): String = path.getOrElse(i) { "" }

  fun landingOn(glyph: String): SplitflapCellPlan =
    SplitflapCellPlan(
      index, from, glyph, path.toMutableList().also { it[land] = glyph }, delayMs, durationMs,
      easing, dir, land, stepMs, letters, resumeK, resumeF,
    )
}

class SplitflapPlan(
  val version: Int,
  val transition: String,
  val totalMs: Double,
  val loop: Boolean,
  val cells: List<SplitflapCellPlan>,
) {
  /**
   * The first `count` cells, the last landing on `glyph`: tail truncation applied to an animation,
   * so it ends on what the one-line <Text> shows.
   */
  fun truncatedTo(count: Int, glyph: String): SplitflapPlan {
    if (count <= 0 || count >= cells.size) return this
    val kept = cells.subList(0, count).toMutableList()
    kept[count - 1] = kept[count - 1].landingOn(glyph)
    return SplitflapPlan(version, transition, totalMs, loop, kept)
  }

  companion object {
    private const val DEFAULT_STEP_MS = 55.0

    /** Null when the JSON is not an object; a version above 1 decodes with no cells. */
    fun decode(json: String): SplitflapPlan? {
      val root = try {
        JSONObject(json)
      } catch (_: Exception) {
        return null
      }
      val version = root.optDouble("v", 1.0).toInt()
      val cells = ArrayList<SplitflapCellPlan>()
      val raw = root.optJSONArray("cells")
      if (version <= 1 && raw != null) {
        for (i in 0 until raw.length()) {
          raw.optJSONObject(i)?.let { cells.add(decodeCell(it)) }
        }
      }
      return SplitflapPlan(
        version = version,
        transition = root.optStringOrNull("transition") ?: "roll",
        totalMs = max(0.0, root.optDouble("totalMs", 0.0).orZero()),
        loop = root.opt("loop") == true,
        cells = cells,
      )
    }

    private fun decodeCell(o: JSONObject): SplitflapCellPlan {
      val to = o.optStringOrNull("to") ?: ""
      val path = o.optJSONArray("path").strings().ifEmpty { listOf(to) }
      val easing = when (o.optStringOrNull("easing")) {
        "inOut" -> SplitflapEasing.IN_OUT
        "linear" -> SplitflapEasing.LINEAR
        else -> SplitflapEasing.OUT
      }
      val resume = o.optJSONObject("resume")
      return SplitflapCellPlan(
        index = o.optDouble("i", -1.0).orZero().toInt(),
        from = o.optStringOrNull("from") ?: "",
        to = to,
        path = path,
        delayMs = max(0.0, o.optDouble("delayMs", 0.0).orZero()),
        durationMs = max(0.0, o.optDouble("durationMs", 0.0).orZero()),
        easing = easing,
        dir = if (o.optDouble("dir", 1.0) < 0) -1 else 1,
        land = min(path.size - 1.0, max(0.0, o.optDouble("land", path.size - 1.0).orZero())).toInt(),
        stepMs = max(1.0, o.optDouble("stepMs", DEFAULT_STEP_MS).let { if (it.isNaN()) DEFAULT_STEP_MS else it }),
        letters = splitLetters(o.optStringOrNull("letters") ?: ""),
        resumeK = resume?.optDouble("k", 0.0)?.orZero()?.toInt(),
        resumeF = resume?.optDouble("f", 0.0)?.orZero() ?: 0.0,
      )
    }

    private fun JSONObject.optStringOrNull(key: String): String? = opt(key) as? String

    private fun Double.orZero(): Double = if (isNaN()) 0.0 else this

    private fun JSONArray?.strings(): List<String> {
      if (this == null) return emptyList()
      return List(length()) { i -> opt(i) as? String ?: "" }
    }

    private fun splitLetters(text: String): List<String> = splitflapGlyphs(text)
  }
}

/** By code point, as the planner (Array.from) and the shadow node split text, so glyph i has width i. */
fun splitflapGlyphs(text: String): List<String> {
  val glyphs = ArrayList<String>(text.length)
  var i = 0
  while (i < text.length) {
    val next = text.offsetByCodePoints(i, 1)
    glyphs.add(text.substring(i, next))
    i = next
  }
  return glyphs
}

/** The planner's clock (src/planner/timeline.ts), shared by every renderer. */
object SplitflapTimeline {
  /**
   * Position along the path at `t` ms after the plan start: k + f of timeline.ts positionAt, so 0
   * before the cell starts and `land` once it has settled.
   */
  fun progress(cell: SplitflapCellPlan, t: Double): Double {
    val steps = cell.land
    if (steps <= 0 || cell.durationMs <= 0) return steps.toDouble()
    if (t <= cell.delayMs) return 0.0
    val x = (t - cell.delayMs) / cell.durationMs
    return if (x >= 1) steps.toDouble() else steps * cell.easing.ease(x)
  }
}
