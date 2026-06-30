# Mapping estimated allocation of defence resources at the CSD, CMA and province level

This project serves to map where defence spending is going in Canada through historical business data and NAICS codes.

## Definitions

Primary defence is when the 6 digit NAICS code is primarily used for defence, which is based on the nature of the product.

Secondary defence is categorized as when the NAICS codes are related to defence, but contains many other industries.

The following NAICS codes were selected to determine what businesses are deemed as defence related:

{PLACEHOLDER}

## Data download

csd_agg.csv
cma_rural_agg.csv

{PLACEHOLDER}

## Data sources

The NAICS codes selected were from the following data sources:
- Data axle historical business data from the University of Toronto
- ISED
- Purdue
- HS codes

## Steps

1. Gather a list of NAICS codes
2. Filter the data axle historical business data for those specific NAICS codes
3. Convert the postal code values into longitude and latitute values
4. Aggregate the business data to CSDs, CMAs, and provinces using the long/lat values while omitting data for any geometries with less than 2 firms for privacy.
5. Gather total values across each year to normalize each geometry
6. Calculate the location quotients 
7. Place the numerator and denominator files into the /data folder in static
8. Done!