<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { base } from '$app/paths';

	// geojson: the boundary polygons for the active geometry (CSD/CMA/Province)
	// valueByUid: { region_uid -> total_sales_M } for the active year + mode
	// maxValue: max sales across regions, for the color scale
	export let geojson = null;
	export let valueByUid = {};
	export let maxValue = 1;
	export let formatSales = (v) => `${v}`;
	export let recordByUid = {};

	let map;
	let mapContainer;
	let mapLoaded = false;
	let popup;

	const SOURCE_ID = 'regions';
	const FILL_LAYER = 'region-fill';
	const LINE_LAYER = 'region-line';

	// Light -> dark ramp (white to brand dark blue)
	const RAMP = ['#ffffff', '#d6e6ef', '#a9cde0', '#6fa8c9', '#3d7fa6', '#1f4e79'];

	// Build a GeoJSON where each feature carries its sales value as a property
	function enrichGeojson(gj, lookup) {
		if (!gj) return { type: 'FeatureCollection', features: [] };
		return {
			type: 'FeatureCollection',
			features: gj.features.map((f) => {
				const uid = String(f.properties.region_uid);
				const rec = lookup[uid] || {};
				const val = rec.sales;
				return {
					...f,
					properties: {
						...f.properties,
						sales_value: Number.isFinite(val) ? val : null,
						n_firms: rec.n_firms ?? null,
						avg_employees: Number.isFinite(rec.avg_employees) ? rec.avg_employees : null
					}
				};
			})
		};
	}

	function fillColorExpression() {
		const safeMax = Math.max(1, maxValue);
		// Null values render as light grey "no data"
		return [
			'case',
			['==', ['get', 'sales_value'], null],
			'#f0f0f0',
			[
				'interpolate',
				['linear'],
				['get', 'sales_value'],
				0, RAMP[0],
				safeMax * 0.05, RAMP[1],
				safeMax * 0.15, RAMP[2],
				safeMax * 0.35, RAMP[3],
				safeMax * 0.6, RAMP[4],
				safeMax, RAMP[5]
			]
		];
	}

	function updateChoropleth() {
		if (!mapLoaded || !map) return;
		const src = map.getSource(SOURCE_ID);
		if (src) src.setData(enrichGeojson(geojson, recordByUid));  // ← recordByUid
		if (map.getLayer(FILL_LAYER)) {
			map.setPaintProperty(FILL_LAYER, 'fill-color', fillColorExpression());
		}
	}

	$: if (mapLoaded && (geojson || recordByUid || maxValue)) {  // ← recordByUid
		updateChoropleth();
	}

	$: totalSales = Object.values(recordByUid)
		.map((r) => r.sales)
		.filter((v) => Number.isFinite(v))
		.reduce((sum, v) => sum + v, 0);


	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: 'https://tiles.openfreemap.org/styles/positron',
			center: [-95, 50],
			zoom: 3.6,
			minZoom: 2,
			maxZoom: 12,
			attributionControl: false,
			projection: 'globe'
		});

		map.addControl(new maplibregl.NavigationControl({ showCompass: true, showZoom: true }), 'bottom-left');

		map.on('load', () => {
			map.addSource(SOURCE_ID, {
				type: 'geojson',
				data: enrichGeojson(geojson, recordByUid)  // ← recordByUid
			});

			map.addLayer({
				id: FILL_LAYER,
				type: 'fill',
				source: SOURCE_ID,
				paint: {
					'fill-color': fillColorExpression(),
					'fill-opacity': 0.8
				}
			});

			map.addLayer({
				id: LINE_LAYER,
				type: 'line',
				source: SOURCE_ID,
				paint: { 'line-color': '#5a5a5a', 'line-width': 0.4, 'line-opacity': 0.5 }
			});

			map.on('click', FILL_LAYER, (event) => {
				if (!event.features?.length) return;
				const p = event.features[0].properties;
				if (popup) popup.remove();
				const valTxt = p.sales_value == null ? 'Suppressed / no data' : formatSales(Number(p.sales_value));
				const firmsTxt = p.n_firms ?? 'N/A';
				const empTxt = (p.avg_employees == null || p.avg_employees === '')
					? 'N/A'
					: Number(p.avg_employees).toFixed(0);

				popup = new maplibregl.Popup({ closeButton: true, closeOnClick: true })
					.setLngLat(event.lngLat)
					.setHTML(
						`<div style="font-family: OpenSans, sans-serif; font-size: 13px; line-height: 1.4;">
							<div style="font-weight: 600; margin-bottom: 4px;">${p.region_name}</div>
							<div>Sales: ${valTxt}</div>
							<div>Firms: ${firmsTxt}</div>
							<div>Avg. employees: ${empTxt}</div>
						</div>`
					)
					.addTo(map);
			});

			map.on('mouseenter', FILL_LAYER, () => { map.getCanvas().style.cursor = 'pointer'; });
			map.on('mouseleave', FILL_LAYER, () => { map.getCanvas().style.cursor = ''; });

			mapLoaded = true;
			updateChoropleth();
		});

		map.on('style.load', () => {
			map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
			map.on('zoom', () => {
				map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
			});
		});
	});

	onDestroy(() => {
		if (popup) popup.remove();
		if (map) map.remove();
		popup = null;
		map = null;
	});
</script>

<div class="map-wrapper">
	<div class="map" bind:this={mapContainer}>
	<div class="map-wrapper">
		<div class="total-overlay">
			<div class="total-label">Total sales (shown)</div>
			<div class="total-value">{formatSales(totalSales)}</div>
		</div>
	</div>
	</div>
</div>

<style>
	.total-overlay {
		position: absolute;
		top: 12px;
		right: 12px;
		background: rgba(255, 255, 255, 0.92);
		border: 1px solid var(--brandGray);
		border-radius: 6px;
		padding: 8px 12px;
		font-family: OpenSans;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.12);
		z-index: 1;
		pointer-events: none;
	}
	.total-label {
		font-size: 11px;
		color: var(--brandGray70);
		font-family: OpenSansBold;
		margin-bottom: 2px;
	}
	.total-value {
		font-size: 20px;
		font-family: TradeGothicBold;
		color: var(--brandDarkBlue);
	}

	.map-wrapper {
		position: relative;
		width: 100%;
		max-width: 1080px;
		margin: 0 auto;
		height: 62vh;
		min-height: 460px;
		border: 1px solid var(--brandGray);
	}
	.map { width: 100%; height: 100%; }
	:global(.maplibregl-popup-content) {
		border-radius: 12px;
		box-shadow: 0 10px 28px rgba(0, 0, 0, 0.2);
	}
	:global(.maplibregl-ctrl-bottom-left) { margin: 16px; }
	@media (max-width: 720px) {
		.map-wrapper { height: 58vh; min-height: 380px; }
	}
</style>