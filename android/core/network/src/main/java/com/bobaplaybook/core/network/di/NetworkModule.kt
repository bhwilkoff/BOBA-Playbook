package com.bobaplaybook.core.network.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import javax.inject.Singleton
import kotlinx.serialization.json.Json

/**
 * Hilt module — provides the shared Ktor [HttpClient] for every
 * Worker / Supabase / pricing-service call.
 *
 * Single client = single connection pool, single TLS session cache.
 * Pairs with the OkHttp client shared with Coil 3 (per
 * [BOBAApplication.sharedHttpClient]) when ANDROID-DEV.md §5.5's
 * shared-OkHttp recipe lands.
 */
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideHttpClient(): HttpClient = HttpClient(OkHttp) {
        install(HttpTimeout) {
            connectTimeoutMillis = 15_000
            requestTimeoutMillis = 30_000
        }
        install(ContentNegotiation) {
            json(
                Json {
                    ignoreUnknownKeys = true
                    coerceInputValues = true
                    isLenient = true
                }
            )
        }
    }
}
