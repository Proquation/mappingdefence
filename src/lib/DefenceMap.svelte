<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { base } from '$app/paths';

	export let data = [];
	export let maxSales = 1;

	let map;
	let mapContainer;
	let mapLoaded = false;
	let popup;
	let selectedFeatureId = null;

	const minRadius = 3;
	const maxRadius = 28;

	function toGeoJson(rows) {
		return {
			type: 'FeatureCollection',
			features: rows.map((row, index) => ({
				type: 'Feature',
				id: index,
				geometry: {
					type: 'Point',
					coordinates: [row.lon, row.lat]
				},
				properties: {
					name: row.name,
					naicsCode: row.naicsCode,
					naicsDesc: row.naicsDesc,
					sales: row.sales,
					employees: row.employees,
					province: row.province,
					city: row.city,
					color: row.color
				}
			}))
		};
	}

	function formatSales(value) {
		if (!Number.isFinite(value)) return 'N/A';
		if (value >= 1000) return `${(value / 1000).toFixed(1)}B`;
		return `${value.toFixed(1)}M`;
	}

	function formatEmployees(value) {
		if (!Number.isFinite(value)) return 'N/A';
		return value.toLocaleString();
	}

	function updateData() {
		if (!mapLoaded || !map) return;
		const source = map.getSource('companies');
		const geojson = toGeoJson(data);
		if (source) {
			source.setData(geojson);
		}
	}

	function updateOpacity() {
		if (!mapLoaded || !map) return;
		const opacity = selectedFeatureId === null
			? 0.85
			: ['case', ['==', ['id'], selectedFeatureId], 0.95, 0.2];
		map.setPaintProperty('company-circles', 'circle-opacity', opacity);
	}

	function updateRadius() {
		if (!mapLoaded || !map) return;
		const safeMax = Math.max(1, maxSales);
		map.setPaintProperty('company-circles', 'circle-radius', [
			'interpolate',
			['linear'],
			['sqrt', ['get', 'sales']],
			0,
			minRadius,
			Math.sqrt(safeMax),
			maxRadius
		]);
	}

	$: if (mapLoaded && data) {
			updateData();
			updateRadius();
			updateOpacity();
	}

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: 'https://tiles.openfreemap.org/styles/positron',
			// style: {
			// 	version: 8,
			// 	// projection: { name: 'globe' },
				
			// 	sources: {
			// 		osm: {
			// 			type: 'vector',
			// 			tiles: ['https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt']
			// 		}
			// 	},
			// 	layers: [
			// 		{ id: 'background', type: 'background', paint: { 'background-color': '#f8f7f3' } },
			// 		{ id: 'ocean', type: 'fill', source: 'osm', 'source-layer': 'ocean', paint: { 'fill-color': '#dfeef6' } },
			// 		{ id: 'land', type: 'fill', source: 'osm', 'source-layer': 'land', paint: { 'fill-color': '#f7f4ee' } },
			// 		{ id: 'boundaries', type: 'line', source: 'osm', 'source-layer': 'boundaries', paint: { 'line-color': '#c6c2b9', 'line-width': 1 } }
			// 	]
			// },
			center: [-95, 50],
			zoom: 3.6,
			minZoom: 2,
			maxZoom: 12,
			pitch: 0,
			bearing: 0,
			scrollZoom: true,
			attributionControl: false,
			projection: 'globe'
		});

		map.addControl(new maplibregl.NavigationControl({ showCompass: true, showZoom: true }), 'bottom-left');

		map.on('load', () => {
			map.addSource('province_state_lines', {
				type: 'geojson',
				data: `${base}/geojson/province-state-lines.geojson`
			});

			map.addLayer({
				id: 'province_state_lines',
				type: 'line',
				source: 'province_state_lines',
				paint: {
					'line-color': '#bdb7aa',
					'line-width': 1,
					'line-opacity': 0.6
				}
			});

			map.addSource('city_names', {
				type: 'geojson',
				data: `${base}/geojson/populated-places-canada.geojson`
			});

			map.addLayer({
				id: 'city_names_big',
				type: 'symbol',
				source: 'city_names',
				layout: {
					'text-field': ['get', 'name'],
					'text-font': ['Open Sans Regular'],
					'text-size': ['interpolate', ['linear'], ['zoom'], 4, 10, 10, 13],
					'text-anchor': 'center',
					'symbol-sort-key': ['get', 'scalerank']
				},
				paint: { 'text-color': '#333333', 'text-halo-color': '#fff', 'text-halo-width': 1.5, 'text-opacity': 0.8 },
				filter: ['<', ['get', 'scalerank'], 5],
				minzoom: 2,
				maxzoom: 6
			});

			map.addLayer({
				id: 'city_names_all',
				type: 'symbol',
				source: 'city_names',
				layout: {
					'text-field': ['get', 'name'],
					'text-font': ['Open Sans Regular'],
					'text-size': ['interpolate', ['linear'], ['zoom'], 4, 10, 10, 13],
					'text-anchor': 'center',
					'symbol-sort-key': ['get', 'scalerank']
				},
				paint: { 'text-color': '#333333', 'text-halo-color': '#fff', 'text-halo-width': 1.5, 'text-opacity': 0.8 },
				minzoom: 6,
				maxzoom: 8
			});

			map.addSource('companies', {
				type: 'geojson',
				data: toGeoJson(data)
			});

			map.addLayer({
				id: 'company-circles',
				type: 'circle',
				source: 'companies',
				paint: {
					'circle-color': ['get', 'color'],
					'circle-opacity': 0.85,
					'circle-stroke-color': '#2a2a2a',
					'circle-stroke-width': 0.6
				}
			});

			updateRadius();
			updateOpacity();

			map.on('click', 'company-circles', (event) => {
				if (!event.features?.length) return;
				const props = event.features[0].properties;
				selectedFeatureId = event.features[0].id ?? null;
				updateOpacity();
				if (popup) popup.remove();

				popup = new maplibregl.Popup({ closeButton: true, closeOnClick: true })
					.setLngLat(event.lngLat)
					.setHTML(
						`<div style="font-family: 'Space Grotesk', sans-serif; font-size: 13px; line-height: 1.4;">
							<div style="font-weight: 600; margin-bottom: 4px;">${props.name}</div>
							<div>${props.city}, ${props.province}</div>
							<div>NAICS ${props.naicsCode}: ${props.naicsDesc}</div>
							<div>Sales: ${formatSales(Number(props.sales))}</div>
							<div>Employees: ${formatEmployees(Number(props.employees))}</div>
						</div>`
					)
					.addTo(map);
			});

			map.on('click', (event) => {
				const features = map.queryRenderedFeatures(event.point, { layers: ['company-circles'] });
				if (features.length) return;
				selectedFeatureId = null;
				updateOpacity();
				if (popup) popup.remove();
			});

			map.on('mouseenter', 'company-circles', () => {
				map.getCanvas().style.cursor = 'pointer';
			});
			map.on('mouseleave', 'company-circles', () => {
				map.getCanvas().style.cursor = '';
			});

			mapLoaded = true;
		});

		map.on('style.load', () => {
			map.setProjection({ type: (map.getZoom() < 7) ? 'globe' : 'mercator' });
			map.on('zoom', () => {
				map.setProjection({ type: (map.getZoom() < 7) ? 'globe' : 'mercator' });
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
	<div class="map" bind:this={mapContainer}></div>
</div>

<style>
	.map-wrapper {
		position: relative;
		width: 100%;
		max-width: 1080px;
		margin: 0 auto;
		height: 62vh;
		min-height: 460px;
		border: 1px solid var(--brandGray);
		border-radius: 0px;
	}

	.map {
		width: 100%;
		height: 100%;
	}

	:global(.maplibregl-popup-content) {
		border-radius: 12px;
		box-shadow: 0 10px 28px rgba(0, 0, 0, 0.2);
	}

	:global(.maplibregl-ctrl-bottom-left) {
		margin: 16px;
	}

	@media (max-width: 720px) {
		.map-wrapper {
			height: 58vh;
			min-height: 380px;
		}
	}
</style>
