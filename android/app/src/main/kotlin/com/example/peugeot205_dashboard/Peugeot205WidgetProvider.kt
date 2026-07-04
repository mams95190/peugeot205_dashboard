package com.example.peugeot205_dashboard

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class Peugeot205WidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }
}

internal fun updateAppWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val prefs = HomeWidgetPlugin.getData(context)
    val water = prefs.getString("water", "-- °C")
    val oil = prefs.getString("oil", "-- °C")
    val press = prefs.getString("press", "-- bar")
    val mode = prefs.getString("mode", "REEL")
    val waterColor = prefs.getString("waterColor", "#55BDE8") ?: "#55BDE8"
    val oilColor = prefs.getString("oilColor", "#D7A33F") ?: "#D7A33F"
    val pressColor = prefs.getString("pressColor", "#FF8A00") ?: "#FF8A00"

    val views = RemoteViews(context.packageName, R.layout.peugeot205_widget).apply {
        setTextViewText(R.id.widget_mode, mode)
        setTextViewText(R.id.widget_water, water)
        setTextViewText(R.id.widget_oil, oil)
        setTextViewText(R.id.widget_press, press)
        setTextColor(R.id.widget_water, Color.parseColor(waterColor))
        setTextColor(R.id.widget_oil, Color.parseColor(oilColor))
        setTextColor(R.id.widget_press, Color.parseColor(pressColor))
    }

    appWidgetManager.updateAppWidget(appWidgetId, views)
}
