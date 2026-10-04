package com.splitflap

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event

/** `onTransitionStart` of SplitflapViewNativeComponent.ts: a transition to this text began to play. */
class TransitionStartEvent(
  surfaceId: Int,
  viewId: Int,
  private val text: String,
) : Event<TransitionStartEvent>(surfaceId, viewId) {
  override fun getEventName(): String = NAME

  // A start that is then interrupted in the same frame is still a start the app may count.
  override fun canCoalesce(): Boolean = false

  override fun getEventData(): WritableMap = Arguments.createMap().apply { putString("text", text) }

  companion object {
    const val NAME = "topTransitionStart"
  }
}
