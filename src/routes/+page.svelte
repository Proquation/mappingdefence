<script>

	import '$lib/assets/global-styles.css';

	import Logo from '$lib/LogoTop.svelte';
	import TitleFullPage from '$lib/TitleFullPage.svelte';
	import TitleHalfSplit from '$lib/TitleHalfSplit.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import ImageSingle from '$lib/ImageSingle.svelte';
	import GraphicSingle from '$lib/GraphicSingle.svelte';
	import GraphicsMultiples from '$lib/GraphicMultiples.svelte';
	import Footer from '$lib/Footer.svelte';
	import Password from '$lib/Password.svelte';
	import Footnote from '$lib/Footnote.svelte';
	import Footnotes from '$lib/Footnotes.svelte';
	import { createFootnoteStore } from '$lib/footnoteUtils';

	const footnoteStore = createFootnoteStore();
	const { footnotes, addFootnote } = footnoteStore;

	const fns = [
		'Hello I am a footnote',
		'Hello I am a second <a href="https://example.com" target="_blank">footnote</a> with a link',
		'Author (Year) Publication information etc this might be a citation or a reference to a source',
		'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas consequat lacus eu dolor dapibus sodales. Aenean venenatis metus id eleifend tincidunt. Nulla ut lacus et urna finibus bibendum sit amet et ante. Aliquam tristique, ex sed porttitor hendrerit, ex odio accumsan ex, eu maximus leo quam quis nulla.'
	];

</script>



<svelte:head>

	<title>Mapping defence | School of Cities</title>

	<meta name="description" content="Examining potential local impacts on jobs and businesses across Canada via maps and charts" />
	<meta name="author" content="School of Cities">
	<meta rel="canonical" href="https://schoolofcities.github.io/tariffs/">

	<meta property="og:title" content="Mapping tariffs" />
	<meta property="og:description" content="Examining potential local impacts on jobs and businesses across Canada via maps and charts" />
	<meta property="og:type" content="website" />
	<meta property="og:url" content="https://schoolofcities.github.io/tariffs/" />
	<meta property="og:image" content="https://raw.githubusercontent.com/schoolofcities/tariffs/main/static/web-card.png" />
	<meta property="og:locale" content="en_CA">

	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content="Mapping defence" />
	<meta name="twitter:description" content="Examining potential local impacts on jobs and businesses across Canada via maps and charts" />
	<meta name="twitter:site" content="https://schoolofcities.github.io/defence/" />
	<meta name="twitter:image" content="https://raw.githubusercontent.com/schoolofcities/defence/main/static/web-card.png" /> 

</svelte:head>



<!-- 
<Password/> -->


<main>

	<!-- Full page title example -->

	<!-- <TitleFullPage
		title="Fun Captivating Project Title"
		subtitle="Maybe a slightly longer more detailed wordier project subtitle"
		image="https://jamaps.github.io/photos/picimgs/halifax2_2024.jpg"
		imageOpacity=0.9
		imageAltText="A photo"
		titleFontColour="var(--brandWhite)"
		subtitleFontColour="var(--brandWhite)"
		logoType="White"
	/> -->


	<!-- Here is a half split title example: -->

	<!-- <TitleHalfSplit
		title="Fun Captivating Project Title"
		subtitle="Maybe a slightly longer more detailed wordier project subtitle that explains the project"
		image="https://schoolofcities.github.io/eddit/_app/immutable/assets/wood-buffalo-title-img-2.CpYjt7SE.jpg"
		imageAltText="A photo"
		imageCaption="Wood Buffalo skyline."
		imageSource="Wikimedia Commons."
		titleFontColour="var(--brandWhite)"
		titleBorderColour="var(--brandYellow)"
		subtitleFontColour="var(--brandWhite)"
		backgroundColour="var(--brandDarkBlue)"
		logoStyle="Dark"
	/> -->

	
	<!-- Simple title example with logo and subtitle: -->

	<Logo logoType="White" backgroundColor="var(--brandGray90)"/>


	<ImageSingle
		imageURL="./img/mappingdefence.png"
		pageURL="./firms"
		caption=''
		source=''
		maxWidth='680px'
		link='Yes'
	/>

	<TitleStandard
		title="Mapping Defence in Canada"
		subtitle=""
	/>

	<!-- <div class="text">

		<AuthorDate
			authors="<a href='' target='_blank'>Tara Vinodrai</a>, <a href='' target='_blank'>Karen Chapple</a>, <a href='' target='_blank'>Jeff Allen</a>, Muhammad Khalis Bin Samion, Eli Easton, Rick DiFrancesco"
			date="October 2025"
		/>
	
	</div> -->

	<!-- <ImageSingle
		imageURL="./images/border-rainbow-bridge.jpg"
		caption="Rainbow Bridge, Niagara River."
		source='Photo by Lennon Kong on Unsplash.'
		altText=""
		maxWidth="680px"
		link="no"
	/> -->


	<div class="text">	

		<p>
			In the face of global geopolitical realignment, the Carney Administration has recommitted Canada to defence. In March, 2026, Canada officially reached NATO's target of spending 2% of its gross domestic product (GDP) on defence. With a target of 5% of GDP spent on defence by 2035, and a new <a href="https://www.canada.ca/en/department-national-defence/corporate/reports-publications/industrial-strategy/security-sovereignty-prosperity.html">Defence Industrial Strategy</a> in place, Canadian cities and regions are likely to see considerable investment and growth in the next decade. But where? 

		</p>

		<p>
			This website examines the current location of the defence industry (firms, jobs, and sales) and Canadian Forces (bases and stations) across Canada’s cities and metropolitan areas. We also look at the geography of recent defence spending (in the form of contracts) in order to determine which places are likely to benefit in the near future. This then points to the local and regional economic development policies that should be in place to ensure prosperity for all.
		</p>

		<p>
			Overall, we find that:
		</p>
		<ul>
			<li>
				Defence spending continues to concentrate in Canada’s historic industrial centres, in Quebec and Ontario
			</li>

			<li>
				Something on Halifax
			</li>
		</ul>
		

		<!-- <p>
			Recent commitments in the Defence sector under the Carney administration brings about a question of where are these funds allocated, and how are they distributed?
		</p>

		<p>
			Last November, the Finance Minister announced the <a href="https://budget.canada.ca/2025/report-rapport/pdf/budget-2025.pdf">Canada Strong Budget 2025</a>, initiliazing an economic shift to increasing defence spending in Canada.
			Then, on February 17, 2026, Carney launched <a href="https://www.canada.ca/en/department-national-defence/corporate/reports-publications/industrial-strategy/security-sovereignty-prosperity.html#toc1">Canada's Defence Industrial Strategy</a>, highlighting commitments on growing the defence sector such as the "build-partner-buy" program. 
		</p>

		<p>
			In addition, Canada has been selected to host the Defence, Security and Resilience Bank (DSRB), a newly formed international financial institution to increase private defence spending, especially for Small Medium Enterprises (SMEs).
			This strategy captures a couple key elements; sovereignty of the industrial sector and military reinforcement, a push and pull between ISED and the DND. 
			What this means for Canada is in the next 10 years, we will be seeing an increase in the share of defence acquisitions, defence research and development, defence revenue and exports, and 125,000 new jobs.
		</p>

		<p>	
			Although the Defence Industrial Strategy outlines broad programs for investment, the question remains as to what this entails for different regions across Canada and the employees that work in this sector.
			The articles in this page cover the current and historial landscape of defence spending across metropolitan regions in Canada to discover what areas could see increased investment and growth.
		</p> -->

		<p>
			Explore the pages below to learn more about defence in Canada:
		</p>

		<ul>
		
		<li> 
			Learn about <a href="./definition">what defence means</a> in this context.
		</li>

		<li>
			<a href="./production">Examine visualizations from a national survey</a> on defence goods production across Canada.
		</li>

		<li>
			See <a href="./firms">a map of defence firms in Canada</a>.
		</li>

		<li>
			<a href="./exports">Read about the export of defence products and services</a> from the Department of National Defence.	
		</li>
		
		<li> 
			<a href="./contracts">Explore where Canadian defence firms are benefitting from national contracts</a> and selling their products.
		</li>

		<li> 
			Read about <a href="./methodology">our data sources and methods</a>.
		</li>
		

		</ul>

		<h2>
			Research team
		</h2>

		<p>
			<a href="https://schoolofcities.utoronto.ca/people/karen-chapple/" target="_blank">Karen Chapple, PhD</a> is the Director of the School of Cities and Professor in the Department of Geography & Planning at the University of Toronto.
		</p>

		<p>
			<a href="https://discover.research.utoronto.ca/8035-tara-vinodrai">Tara Vinodrai, PhD</a> is Professor in the Institute for Management and Innovation at the University of Toronto, where she directs the Master of Urban Innovation program.
		</p>

		<p>
			<a href="https://jamaps.github.io/" target="_blank">Jeff Allen, PhD</a> is a Senior Research Associate and the Lead of Data Visualization at the School of Cities at the University of Toronto. 
		</p>

		<p>
			<a href="https://www.linkedin.com/in/yihoi-jung-0b95351b5/" target="_blank">Yihoi Jung</a> is a Data Analyst Research Assistant at the School of Cities and has completed his undergraduate degree at the University of Toronto Scarborough in Statistics and City Studies.
		</p>

		<p>
			<a href='https://www.linkedin.com/in/sarahbridgetgibbons/' target="_blank">Sarah Gibbons</a> is lorem ipsum.
		</p>

		<p>
			<a href="https://www.linkedin.com/in/andrewwfeng/" target="_blank">Andrew Feng</a> is lorem ipsum.
		</p>

	</div>

	<Footer />

</main>