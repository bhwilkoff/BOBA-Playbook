package com.bobaplaybook.core.data.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Empty Hilt module — placeholder for future data-layer bindings
 * (Room database provision, Tink-backed TokenStore, etc.). Keeps the
 * `:core:data` module Hilt-aware from M0 so feature modules can wire
 * `@HiltViewModel`s without later refactor.
 */
@Module
@InstallIn(SingletonComponent::class)
object DataModule
