package uk.me.amugofjava.anytime_podcast_player

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.PowerManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "uk.me.amugofjava.anytime_podcast_player/power"
        ).setMethodCallHandler { call, result ->
            if (call.method == "isPowerSaveMode") {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                result.success(powerManager?.isPowerSaveMode ?: false)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "uk.me.amugofjava.anytime_podcast_player/antennapod_import"
        ).setMethodCallHandler { call, result ->
            if (call.method == "readDatabase") {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("READ_ERROR", "Database path is required.", null)
                    return@setMethodCallHandler
                }

                Thread {
                    var db: SQLiteDatabase? = null
                    try {
                        db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)

                        if (!tableExists(db, "Feeds") || !tableExists(db, "FeedItems")) {
                            runOnUiThread {
                                result.error("INVALID_DATABASE", "Not a valid AntennaPod database.", null)
                            }
                            return@Thread
                        }

                        val hasStateColumn = columnExists(db, "Feeds", "state")
                        val hasFeedMediaTable = tableExists(db, "FeedMedia")

                        val playedByFeed = mutableMapOf<Long, MutableList<Map<String, String?>>>()
                        val playedQuery = if (hasFeedMediaTable) {
                            """
                            SELECT fi.feed, fi.item_identifier, fm.download_url
                            FROM FeedItems fi
                            LEFT JOIN FeedMedia fm ON fm.feeditem = fi.id
                            WHERE fi.read = 1
                            """.trimIndent()
                        } else {
                            """
                            SELECT feed, item_identifier, NULL
                            FROM FeedItems
                            WHERE read = 1
                            """.trimIndent()
                        }

                        db.rawQuery(playedQuery, null).use { cursor ->
                            while (cursor.moveToNext()) {
                                val feedId = cursor.getLong(0)
                                val guid = if (cursor.isNull(1)) null else cursor.getString(1)
                                val mediaUrl = if (cursor.isNull(2)) null else cursor.getString(2)
                                playedByFeed.getOrPut(feedId) { mutableListOf() }.add(
                                    mapOf("guid" to guid, "mediaUrl" to mediaUrl)
                                )
                            }
                        }

                        val feedsQuery = buildString {
                            append("SELECT id, title, download_url FROM Feeds ")
                            append("WHERE download_url IS NOT NULL AND TRIM(download_url) != '' ")
                            append("AND download_url NOT LIKE 'antennapod_local:%'")
                            if (hasStateColumn) {
                                append(" AND state = 0")
                            }
                        }

                        val feeds = mutableListOf<Map<String, Any?>>()
                        db.rawQuery(feedsQuery, null).use { cursor ->
                            while (cursor.moveToNext()) {
                                val feedId = cursor.getLong(0)
                                val title = if (cursor.isNull(1)) "" else cursor.getString(1)
                                val feedUrl = if (cursor.isNull(2)) "" else cursor.getString(2).trim()
                                if (feedUrl.isNotEmpty()) {
                                    feeds.add(
                                        mapOf(
                                            "title" to title,
                                            "feedUrl" to feedUrl,
                                            "playedItems" to (playedByFeed[feedId] ?: emptyList<Map<String, String?>>())
                                        )
                                    )
                                }
                            }
                        }

                        runOnUiThread {
                            result.success(feeds)
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("READ_ERROR", e.message, null)
                        }
                    } finally {
                        db?.close()
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun tableExists(db: SQLiteDatabase, tableName: String): Boolean {
        return db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            arrayOf(tableName)
        ).use { it.moveToFirst() }
    }

    private fun columnExists(db: SQLiteDatabase, tableName: String, columnName: String): Boolean {
        return db.rawQuery("PRAGMA table_info($tableName)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                if (nameIndex >= 0 && cursor.getString(nameIndex) == columnName) {
                    return true
                }
            }
            false
        }
    }
}
