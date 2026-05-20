package com.bobaplaybook.core.network.di

import com.bobaplaybook.core.network.SupabaseConfig
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
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

    /**
     * Single Supabase client for the entire app — Auth + Postgrest
     * both flow through this instance so the session token JWT is
     * shared between AuthManager (sign-in) and the data repositories
     * (user_cards, decks, etc).
     *
     * supabase-kt's SessionManager auto-refreshes the JWT on expiry,
     * which covers the iOS `refreshIfNeeded()` lesson (memory
     * `feedback_refresh_jwt_for_workers_and_storage`).
     */
    @Provides
    @Singleton
    fun provideSupabaseClient(): SupabaseClient = createSupabaseClient(
        supabaseUrl = SupabaseConfig.URL,
        supabaseKey = SupabaseConfig.PUBLISHABLE_KEY,
    ) {
        install(Auth)
        install(Postgrest)
    }
}
