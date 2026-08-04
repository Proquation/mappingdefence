<script>
	import '$lib/assets/global-styles.css';
	import Logo from '$lib/LogoTop.svelte';
	import Footer from '$lib/Footer.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';
</script>

<Logo logoType="White" backgroundColor="var(--brandGray90)" />

<main class="page">
	<TitleStandard title="What is defence?" />
	<div class="text">
		<AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://discover.research.utoronto.ca/8035-tara-vinodrai' target='_blank'>Tara Vinodrai</a>, 
            <a href='https://www.geography.utoronto.ca/people/directories/all-faculty/richard-difrancesco'>Richard DiFrancesco</a>, <a href='https://www.linkedin.com/in/sarahbridgetgibbons/'>Sarah Gibbons</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>"
			date="August 2026."
		/>
		<p>
            Researchers have long struggled to identify economic activity connected to national defence spending. 
			There is no established list of firms or even industries producing military goods and services. 
			Instead, research typically relies on selected codes associated with the military in the North American Industry Classification System (NAICS) to identify firms. 
			A small set of industries work almost exclusively on military goods and services; we refer to these as “core” or “primary.” A much larger set of industries produces for the military but also many civilian sectors (e.g., engineering services); we refer to these as “defence-related” or “secondary.” 
			Below is the classification we use to identify primary and secondary firms.
		</p>

		<p>PLACEHOLDER for table of naics, then another explanation needed for contracts</p>
	</div>

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