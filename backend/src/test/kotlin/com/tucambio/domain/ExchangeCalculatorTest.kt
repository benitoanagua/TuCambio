package com.tucambio.domain

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class ExchangeCalculatorTest {
    private val pair = CurrencyPair.of("AAA", "BBB")
    private val rate = CurrencyRate(
        buy = BigDecimal("0.00705"),
        sell = BigDecimal("0.00741")
    )

    @Test
    fun baseToQuoteUsesBuyRateAndTargetPrecision() {
        val source = CurrencyAmount.of("AAA", BigDecimal("1780000.00"), 2)

        val result = ExchangeCalculator.convert(
            source, "BBB", 2, pair, rate, RoundingMode.HALF_EVEN
        )

        assertEquals("BBB", result.currencyCode)
        assertEquals(BigDecimal("12549.00"), result.amount)
    }

    @Test
    fun quoteToBaseUsesSellRateAndDivides() {
        val source = CurrencyAmount.of("BBB", BigDecimal("2260.00"), 2)

        val result = ExchangeCalculator.convert(
            source, "AAA", 2, pair, rate, RoundingMode.HALF_EVEN
        )

        assertEquals(BigDecimal("304993.25"), result.amount)
    }

    @Test
    fun targetCurrencyPrecisionIsNotAssumedToBeTwoDecimals() {
        val source = CurrencyAmount.of("AAA", BigDecimal("10.00"), 2)
        val threeDecimalRate = CurrencyRate(BigDecimal("1.23456"), BigDecimal("1.25000"))

        val result = ExchangeCalculator.convert(
            source, "BBB", 3, pair, threeDecimalRate, RoundingMode.HALF_UP
        )

        assertEquals(BigDecimal("12.346"), result.amount)
        assertEquals(3, result.decimalPlaces)
    }

    @Test
    fun roundingPolicyMustBeExplicitAndIsAppliedAtTargetPrecision() {
        val source = CurrencyAmount.of("AAA", BigDecimal("1.00"), 2)
        val tieRate = CurrencyRate(BigDecimal("1.005"), BigDecimal("1.005"))

        val halfUp = ExchangeCalculator.convert(
            source, "BBB", 2, pair, tieRate, RoundingMode.HALF_UP
        )
        val halfEven = ExchangeCalculator.convert(
            source, "BBB", 2, pair, tieRate, RoundingMode.HALF_EVEN
        )

        assertEquals(BigDecimal("1.01"), halfUp.amount)
        assertEquals(BigDecimal("1.00"), halfEven.amount)
    }

    @Test
    fun amountWithExcessNonZeroFractionalDigitsIsRejected() {
        assertFailsWith<IllegalArgumentException> {
            CurrencyAmount.of("AAA", BigDecimal("1.001"), 2)
        }
    }

    @Test
    fun pairMismatchIsRejected() {
        val source = CurrencyAmount.of("AAA", BigDecimal("10.00"), 2)

        assertFailsWith<IllegalArgumentException> {
            ExchangeCalculator.convert(
                source, "CCC", 2, pair, rate, RoundingMode.HALF_EVEN
            )
        }
    }

    @Test
    fun nonPositiveRatesAndAmountsAreRejected() {
        assertFailsWith<IllegalArgumentException> {
            CurrencyRate(BigDecimal.ZERO, BigDecimal.ONE)
        }
        assertFailsWith<IllegalArgumentException> {
            CurrencyAmount.of("AAA", BigDecimal.ZERO, 2)
        }
    }
}
