package com.splitflap

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.ReactStylesDiffMap
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.StateWrapper
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.SplitflapViewManagerDelegate
import com.facebook.react.viewmanagers.SplitflapViewManagerInterface

@ReactModule(name = SplitflapViewManager.NAME)
class SplitflapViewManager : SimpleViewManager<SplitflapView>(),
  SplitflapViewManagerInterface<SplitflapView> {
  private val delegate: ViewManagerDelegate<SplitflapView> = SplitflapViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<SplitflapView> = delegate

  override fun getName(): String = NAME

  public override fun createViewInstance(context: ThemedReactContext): SplitflapView =
    SplitflapView(context)

  override fun updateState(
    view: SplitflapView,
    props: ReactStylesDiffMap?,
    stateWrapper: StateWrapper?,
  ): Any? {
    stateWrapper?.stateData?.let {
      view.setMeasured(it)
      view.commit()
    }
    return null
  }

  override fun onAfterUpdateTransaction(view: SplitflapView) {
    super.onAfterUpdateTransaction(view)
    view.commit()
  }

  @ReactProp(name = "text")
  override fun setText(view: SplitflapView, value: String?) {
    view.text = value ?: ""
  }

  @ReactProp(name = "plan")
  override fun setPlan(view: SplitflapView, value: String?) {
    view.plan = value ?: ""
  }

  @ReactProp(name = "fontFamily")
  override fun setFontFamily(view: SplitflapView, value: String?) {
    view.fontFamily = value
  }

  @ReactProp(name = "fontSize")
  override fun setFontSize(view: SplitflapView, value: Float) {
    view.fontSize = value
  }

  @ReactProp(name = "fontWeight")
  override fun setFontWeight(view: SplitflapView, value: String?) {
    view.fontWeight = value
  }

  @ReactProp(name = "fontStyle")
  override fun setFontStyle(view: SplitflapView, value: String?) {
    view.fontStyle = value
  }

  @ReactProp(name = "fontVariant")
  override fun setFontVariant(view: SplitflapView, value: ReadableArray?) {
    view.fontVariant = value?.toArrayList()?.mapNotNull { it as? String } ?: emptyList()
  }

  @ReactProp(name = "glyphs")
  override fun setGlyphs(view: SplitflapView, value: ReadableArray?) {
    view.cells = value?.toArrayList()?.mapNotNull { it as? String } ?: emptyList()
  }

  @ReactProp(name = "cellWidth")
  override fun setCellWidth(view: SplitflapView, value: String?) {
    view.cellWidth = value ?: "natural"
  }

  // The shadow node measures the `uniform` and `tiered` widths from these; the view reads them from
  // the state.
  @ReactProp(name = "widthGlyphs")
  override fun setWidthGlyphs(view: SplitflapView, value: String?) = Unit

  @ReactProp(name = "color", customType = "Color")
  override fun setColor(view: SplitflapView, value: Int?) {
    view.color = value
  }

  // Both already live in what the shadow node measured: spacing in the cell widths each glyph is
  // placed at, line height in the ascent its baseline sits at. Setting either on the paint too
  // would count it twice.
  @ReactProp(name = "letterSpacing")
  override fun setLetterSpacing(view: SplitflapView, value: Float) {}

  @ReactProp(name = "lineHeight")
  override fun setLineHeight(view: SplitflapView, value: Float) {}

  @ReactProp(name = "allowFontScaling")
  override fun setAllowFontScaling(view: SplitflapView, value: Boolean) {
    view.allowFontScaling = value
  }

  @ReactProp(name = "maxFontSizeMultiplier")
  override fun setMaxFontSizeMultiplier(view: SplitflapView, value: Float) {
    view.maxFontSizeMultiplier = value
  }

  @ReactProp(name = "surfaceColor", customType = "Color")
  override fun setSurfaceColor(view: SplitflapView, value: Int?) {
    view.surfaceColor = value
  }

  @ReactProp(name = "reduceMotion")
  override fun setReduceMotion(view: SplitflapView, value: String?) {
    view.reduceMotion = value ?: "system"
  }

  override fun prepareToRecycleView(reactContext: ThemedReactContext, view: SplitflapView): SplitflapView? {
    view.prepareToRecycle()
    return super.prepareToRecycleView(reactContext, view)
  }

  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
    (super.getExportedCustomDirectEventTypeConstants() ?: emptyMap()) +
      mapOf(
        TransitionStartEvent.NAME to mapOf("registrationName" to "onTransitionStart"),
        TransitionEndEvent.NAME to mapOf("registrationName" to "onTransitionEnd"),
      )

  companion object {
    const val NAME = "SplitflapView"
  }
}
