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




<Password/>


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

	<Logo logoType="Blue" backgroundColor="var(--brandWhite)"/>


	<ImageSingle
		imageURL="./img/mappingdefence.png"
		caption=''
		source=''
		maxWidth='680px'
		link='No'
	/>

	<TitleStandard
		title="Mapping Defence"
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
			Recent commitments in the Defence sector under the Carney administration brings about a question of where are these funds allocated, and how are they distributed?
			Although Budget 2025 outlines broad programs for investment, the question remains as to what this entails for different regions across Canada and the employees that work in this sector.
		</p>


		<ul>
		<li>
			<a href="./national-survey-comparison">Examine graphs from a national survey</a> on defence expenditures across Canada.
		</li>

		<li>
			<a href="./company-insights">Read about the companies that make up our defence industry</a>.	
		</li>

		</ul>

		<h2>
			Research team
		</h2>

		<p>
			<a href="https://discover.research.utoronto.ca/8035-tara-vinodrai">Tara Vinodrai, PhD</a> is Professor in the Institute for Management and Innovation at the University of Toronto, where she directs the Master of Urban Innovation program.
		</p>

		<p>
			<a href="https://schoolofcities.utoronto.ca/people/karen-chapple/" target="_blank">Karen Chapple, PhD</a> is the Director of the School of Cities and Professor in the Department of Geography & Planning at the University of Toronto.
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
			<a href="https://www.linkedin.com/in/eli-easton-77bb60273/" target="_blank">Andrew Feng</a> is lorem ipsum.
		</p>

		<!-- https://armstransfers.sipri.org/ArmsTransfer/ -->

	</div>

	<Footer />

</main>