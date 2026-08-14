<script>
	import '$lib/assets/global-styles.css';
	import Logo from '$lib/LogoTop.svelte';
	import Footer from '$lib/Footer.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';
	
	import { base } from '$app/paths';
</script>

<Logo logoType="White" backgroundColor="var(--brandGray90)" />

<main class="page">
	<TitleStandard title="Data methodology" />
	<div class="text">
		<AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://discover.research.utoronto.ca/8035-tara-vinodrai' target='_blank'>Tara Vinodrai</a>, 
			<a href='https://www.linkedin.com/in/sarahbridgetgibbons/'>Sarah Gibbons</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>"
			date="August 2026."
		/>
		<p>
            This project draws on three data sources:
		</p>
		<ul>
			<li> 
				The <a href="https://www.statcan.gc.ca/en/survey/business/2933">Canadian Defence, Aerospace and Commercial and Civil Marine Sectors Survey</a> (CDACCMS) creates a general summary of the businesses engaged in the defence, aerospace, marine and cybersecurity sectors in Canada.
			</li>
			<li>
				Data Axle (available via the University of Toronto Library) provides data for individual private firms related to the North American Industrial Classification System (NAICS) codes.
			</li>
			<li>
				Contract data from the <a href="https://search.open.canada.ca/contracts/?owner_org=dnd-mdn&page=1&sort=contract_date+desc">Government of Canada's disclosure of contracts over $10,000</a>,
			    to analyze contracts issued by Department of National Defence.
			</li>
		</ul>

		<h2>National survey</h2>

		<h2>Data axle</h2>

		<p>Jobs in this context refers to employees within headquarter firms, which is a metric given in the Data Axle.</p>

		<p>
			"Primary defence" is deemed as NAICS codes where the companies' sales are their primarily
			defence-related. "Secondary defence" is when defence is not the primary product that these companies
			produce. For example, engineering services fall under many different sectors, but companies like <a
				href="https://www.wsp.com/en-me/sectors/defense">Williams Sale Partnership (WSP)</a
			> span dozens of different sectors, one of them being defence.
		</p>
		<p>
			To protect firm-level confidentiality, regions with fewer than 2 firms in a given category and
			year have their exact sales suppressed and appear as "no data" on the map.
		</p>

		<p>
			Download data:
			<a href="{base}/data/csd_agg.csv" download>Census Subdivisions</a> ·
			<a href="{base}/data/cma_rural_agg.csv" download>Census Metropolitan Areas</a> ·
			<a href="{base}/data/prov_agg.csv" download>Provinces</a> ·
			<a href="{base}/data/Master NAICS Codes List - Full list.csv" download>NAICS codes used to filter the data axle</a>
		</p>

		<h2>Contracts</h2>
		<p>
			Each contract is classified into a defence-relevance tier (Core Defence, Technical Support, or General Government Support) and an industry sector based on its economic object code. The tiers capture a contract’s relationship to defence capability. Core Defence expenditures capture investments that directly are contracts with an object code related to the provision and production of defence goods and services and directly generate, sustain, or enhance military operational capability. This includes things like weapons systems, military platforms (aircraft, ships and vehicles) and specialized defence infrastructure. Industrial and technical support contracts are expenditures that enable defence production, maintenance and logistics but do not themselves constitute military capability such as engineering services, fuel, and IT support. These object codes are items that could exist outside of defence, but are still supporting defence activities. Contracts falling under the General Government Support tier are the least related to defence. 
			Instead, they are associated with operating the Department of National Defence as a government organization rather than producing military capability. 
		</p>
		<p>
			The disclosure data spans 2017–2026. Because contracts are frequently amended, a single procurement can appear multiple times in the raw disclosure records. We retain only the most recent amendment for each unique Procurement Identification Number before analysis. Vendor names are not recorded consistently across contracts, so we applied a standardized cleaning process. Vendor location is geocoded from the Forward Sortation Area (first three digits of the  postal code) reported in the disclosure record. This address is typically a company’s registered address, meaning the location analyzed as where value flows is typically the headquarters rather than necessarily where the associated economic activity occurs. Postal code reporting is incomplete in the earlier years of the contract data. Two rounds of  fixes were applied to reduce the missingness of these numbers: first was backfilling using the most common historical FSA reported elsewhere for the same vendor, then, where that fails, matching vendor names against the Data Axle historical business location data using fuzzy string matching..  a commercial firm database (Data Axle/D&B) using fuzzy string matching. Backfilling assumes a vendor's location is stable over the period covered by the data; firms that relocated or opened new facilities during the panel may be misattributed to an earlier address. The data from 2023-2026 contains the most complete raw entries for postal code information, meaning these have the most reliable period for analysis. 

		</p>
		<p>
			The contract data also reports contracts given to non-domestic vendors, which are reported with no postal code and instead with a foreign ‘country of vendor’. Any rows with no Canadian province or CMA are excluded from the map view. Some vendors reported as Canadian in the disclosure data are headquartered abroad with a Canadian contracting or subsidiary address. Conversely, for vendors reported with a foreign address, the disclosure data cannot capture whether production or investment associated with the contract occurs in Canada. This distinction matters for assessing Industrial and Technological Benefits (ITB) commitments, this dataset cannot resolve these types of investments. This dataset covers only National Defence's own procurement and does not capture contracts issued by other governments that may also affect the Canadian defence industrial base. 

		</p>
		<p>
			Total Contract Value figures for multi-year contracts reflect the full contracted value rather than annual spending. As such, the year-over-year figures represent the value of the contracts issued in that year, rather than annual defence expenditures or the pace at which funds were disbursed. 

		</p>

		<h3>
			Locating where value flows

		</h3>

		<p>
We geocoded vendor location using the Forward Sortation Area (the first three characters of the postal code) reported in each disclosure record. This is typically a company's registered address, so we are measuring where contract value formally accumulates, generally a firm's headquarters, rather than necessarily where the associated production, employment, or economic activity takes place.
		</p>

		<p>
			Postal code reporting is incomplete in the earlier years of the data, so we apply two rounds of correction to reduce this gap. First, we backfill using the most common historical FSA reported elsewhere for the same vendor. Where that fails, we match vendor names against Data Axle historical business location data using fuzzy string matching. Both approaches assume a vendor's location is stable across the panel; a firm that relocated or opened new facilities during this period could be misattributed to an earlier address. Even with these corrections, 2023–2026 contains the most complete postal code reporting and is the most reliable window for place-based analysis.
		</p>

		<p>
			The contract data also reports contracts given to non-domestic vendors, which are reported with no postal code and instead with a foreign ‘country of vendor’. Any rows with no Canadian province or Census Metropolitan Area (CMA) are excluded from the map view. Some vendors reported as Canadian in the disclosure data are headquartered abroad with a Canadian contracting or subsidiary address. Conversely, for vendors reported with a foreign address, the disclosure data cannot capture whether production or investment associated with the contract occurs in Canada. This distinction matters for assessing Industrial and Technological Benefits (ITB) commitments, this dataset cannot resolve these types of investments. This dataset covers only National Defence's own procurement and does not capture contracts issued by other governments that may also shape the Canadian defence industrial base. 
		</p>

		<p>
			Notably, the contracts represented here are with prime contractors: the vendors who hold the direct relationship with the Department of National Defence and are the first point of contact for a given procurement. However, prime contractors routinely subcontract work down through a broader supply chain, and it's through this subcontracting that the complete picture of a contract's regional economic impact is ultimately felt. We don't have visibility into this subcontracting layer. Publicly available procurement data captures only the prime relationship, not what happens beneath it.
		</p>



	</div>

	

	<!-- <div class="text" style="margin-bottom: 0px;">
		<h3>Data sources and methods</h3>
		<p>
			The company sales volume data is from the <a
				href="https://mdl.library.utoronto.ca/technology/tutorials/working-data-axle-historical-business-location-data"
				>University of Toronto Library Data Axle</a
			>. In order to identify the companies we wanted to observe from the historical business dataset, we
			gathered a list of NAICS codes deemed to be at least partially defence related.
		</p>
		<p>
			Jobs in this context refers to employees within headquarter firms, which is a metric given in the Data Axle.
		</p>
		<p>
			"Primary defence" is deemed as NAICS codes where the companies' sales are their primarily
			defence-related. "Secondary defence" is when defence is not the primary product that these companies
			produce. For example, engineering services fall under many different sectors, but companies like <a
				href="https://www.wsp.com/en-me/sectors/defense">Williams Sale Partnership (WSP)</a
			> span dozens of different sectors, one of them being defence.
		</p>
		<p>
			To protect firm-level confidentiality, regions with fewer than 2 firms in a given category and
			year have their exact sales suppressed and appear as "no data" on the map.
		</p>

		<p>
			Download data:
			<a href="{base}/data/csd_agg.csv" download>Census Subdivisions</a> ·
			<a href="{base}/data/cma_rural_agg.csv" download>Census Metropolitan Areas</a> ·
			<a href="{base}/data/prov_agg.csv" download>Provinces</a> ·
			<a href="{base}/data/Master NAICS Codes List - Full list.csv" download>NAICS codes used to filter the data axle</a>
		</p>
	</div> -->

	<!-- <div class="text" style="margin-bottom: 0px;">
		<h3>Data sources and methods</h3>
		<p>
			Contract data comes from the <a href="https://search.open.canada.ca/contracts/?owner_org=dnd-mdn&page=1&sort=contract_date+desc">Government of Canada's disclosure of contracts over $10,000</a>,
			filtered to contracts issued by National Defence.
		</p>
		<p>
			Each contract is classified into a defence-relevance <b>tier</b> (Core Defence Industrial Complex,
			Industrial and Technical Support, or General Government Support) and an industry <b>cluster</b> based
			on its economic object code.
		</p>
		<p>
			Vendor locations are geocoded from postal codes. Any rows with no Canadian province or CMA are
			excluded from the map view.
		</p>

		<p>
			Download data:
			<a href="{base}/data/contracts_cma_agg.csv" download>Census Metropolitan Areas</a> ·
			<a href="{base}/data/contracts_prov_agg.csv" download>Provinces</a>
		</p>
	</div> -->

	<!-- <h3>Data methods and source</h3>
		<p>
			Data comes from the <a href="https://www.statcan.gc.ca/en/survey/business/2933">Canadian Defence, Aerospace and Commercial and Civil Marine Sectors Survey</a> (CDACCMS). 
			The survey creates a general summary of the businesses engaged in the defence, aerospace, marine and cybersecurity sectors in Canada to match with the Statistics Canada Business Register.
			A more detailed finding of the most recent survey can be found here INSERT LINK, whereas this serves to compare across all years to see recent trends.
		</p> -->

</main>

<Footer />

<style>
	.page {
		max-width: 1200px;
		margin: 0 auto;
		padding: 20px 24px 80px;
		display: flex;
		flex-direction: column;
		gap: 24px;
	}

	.text {
		font-family: OpenSans;
		color: var(--brandGray90);
		line-height: 1.6;
	}

	@media (max-width: 720px) {
		.page {
			padding: 32px 16px 64px;
		}
	}
</style>