package com.example.peugeot205_dashboard

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
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
    val water = prefs.getString("water", "--")
    val oil = prefs.getString("oil", "--")
    val press = prefs.getString("press", "--")
    val mode = prefs.getString("mode", "--")

    val views = RemoteViews(context.packageName, R.layout.peugeot205_widget).apply {
        setTextViewText(R.id.widget_mode, "Mode: $mode")
        setTextViewText(R.id.widget_water, "Eau: $water")
        setTextViewText(R.id.widget_oil, "Huile: $oil")
        setTextViewText(R.id.widget_press, "Pression: $press")
    }

    appWidgetManager.updateAppWidget(appWidgetId, views)
}
