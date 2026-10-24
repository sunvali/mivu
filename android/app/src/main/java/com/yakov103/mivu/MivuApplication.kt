package com.yakov103.mivu

import android.app.Application
import com.yakov103.mivu.diary.DiaryRepository

class MivuApplication : Application() {
    val repository by lazy { DiaryRepository(this) }
}
