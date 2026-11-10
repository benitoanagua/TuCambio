package com.tucambio.domain

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Locale

/**
 * An exact positive amount expressed in one configured currency.
 *
 * The amount is normalized to the currency's configured precision without
 * rounding. Values that would require rounding are rejected at the boundary.
 */
data class CurrencyAmount private constructor(
    val currencyCode: String,
    val amount: BigDecimal,
    val decimalPlaces: Int
) {
    companion object {
        fun of(currencyCode: String, amount: BigDecimal, decimalPlaces: Int): CurrencyAmount {
            val code = currencyCode.trim().uppercase(Locale.ROOT)
            require(CURRENCY_CODE.matches(code)) { "Invalid currency code" }
            require(decimalPlaces in 0..18) { "Invalid currency precision" }
            require(amount > BigDecimal.ZERO) { "Amount must be positive" }

            val normalized = try {
                amount.setScale(decimalPlaces, RoundingMode.UNNECESSARY)
            } catch (error: ArithmeticException) {
                throw IllegalArgumentException(
                    "Amount exceeds the configured precision for $code",
                    error
                )
            }
            return CurrencyAmount(code, normalized, decimalPlaces)
        }

        private val CURRENCY_CODE = Regex("^[A-Z0-9]{3,12}$")
    }
}

/** A directed pair: base currency quoted in units of quote currency. */
data class CurrencyPair private constructor(
    val baseCurrencyCode: String,
    val quoteCurrencyCode: String
) {
    companion object {
        fun of(baseCurrencyCode: String, quoteCurrencyCode: String): CurrencyPair {
            val base = baseCurrencyCode.trim().uppercase(Locale.ROOT)
            val quote = quoteCurrencyCode.trim().uppercase(Locale.ROOT)
            require(Regex("^[A-Z0-9]{3,12}$").matches(base)) { "Invalid base currency code" }
            require(Regex("^[A-Z0-9]{3,12}$").matches(quote)) { "Invalid quote currency code" }
            require(base != quote) { "A currency pair must contain two different currencies" }
            return CurrencyPair(base, quote)
        }
    }
}

/** Buy and sell rates for the directed pair. Both values must be positive. */
data class CurrencyRate(val buy: BigDecimal, val sell: BigDecimal) {
    init {
        require(buy > BigDecimal.ZERO) { "Buy rate must be positive" }
        require(sell > BigDecimal.ZERO) { "Sell rate must be positive" }
    }
}

/**
 * Converts a verified source amount using the rate side determined by the
 * source currency. The caller must provide the target currency precision and
 * an explicit rounding policy; no financial rounding default is assumed.
 *
 * Base -> quote: amount * buy rate.
 * Quote -> base: amount / sell rate.
 */
object ExchangeCalculator {
    fun convert(
        verifiedSourceAmount: CurrencyAmount,
        targetCurrencyCode: String,
        targetDecimalPlaces: Int,
        pair: CurrencyPair,
        rate: CurrencyRate,
        roundingMode: RoundingMode
    ): CurrencyAmount {
        require(targetDecimalPlaces in 0..18) { "Invalid target currency precision" }

        val targetCode = targetCurrencyCode.trim().uppercase(Locale.ROOT)
        val converted = when {
            verifiedSourceAmount.currencyCode == pair.baseCurrencyCode &&
                targetCode == pair.quoteCurrencyCode ->
                verifiedSourceAmount.amount.multiply(rate.buy)
                    .setScale(targetDecimalPlaces, roundingMode)

            verifiedSourceAmount.currencyCode == pair.quoteCurrencyCode &&
                targetCode == pair.baseCurrencyCode ->
                verifiedSourceAmount.amount.divide(rate.sell, targetDecimalPlaces, roundingMode)

            else -> throw IllegalArgumentException(
                "Source and target currencies must be opposite sides of the selected pair"
            )
        }

        return CurrencyAmount.of(targetCode, converted, targetDecimalPlaces)
    }
}
