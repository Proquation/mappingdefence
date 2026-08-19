library(dplyr)
library(tidyverse)
library(readxl)
library(openxlsx)


cpi_raw <- read.csv("../../analysis/cpi/cpi_2016_2026.csv")

CPI <- setNames(cpi_raw$VALUE, as.character(cpi_raw$REF_DATE))
CPI_BASE_YEAR <- 2025
to_real_dollars <- function(nominal_value, year) {
  cpi_year <- CPI[as.character(year)]
  cpi_base <- CPI[as.character(CPI_BASE_YEAR)]
  ifelse(is.na(cpi_year) | is.na(nominal_value), nominal_value, nominal_value * (cpi_base / cpi_year))
}

# B1B2B3.csv
b1b2b3 <- read.csv("B1B2B3.csv") %>%
  mutate(
    Amount_num = as.numeric(gsub(",", "", trimws(Amount))),
    Amount_real = to_real_dollars(Amount_num, Year)
  )
write.csv(b1b2b3, "B1B2B3.csv", row.names = FALSE)

# B4renamed_normalized.csv
b4 <- read.csv("B4renamed_normalized.csv") %>%
  mutate(
    Sales_real = to_real_dollars(`Sales.of.Goods.and.Services`, Year)
  )
write.csv(b4, "B4renamed_normalized.csv", row.names = FALSE)