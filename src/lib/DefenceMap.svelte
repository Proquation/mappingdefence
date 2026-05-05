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

	const minRadius = 3;
	const maxRadius = 28;

	function toGeoJson(rows) {
		return {
			type: 'FeatureCollection',
			features: rows.map((row) => ({
				type: 'Feature',
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
		}

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: {
				version: 8,
				// projection: { name: 'globe' },
				
				sources: {
					osm: {
						type: 'vector',
						tiles: ['https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt']
					}
				},
				layers: [
					{ id: 'background', type: 'background', paint: { 'background-color': '#f8f7f3' } },
					{ id: 'ocean', type: 'fill', source: 'osm', 'source-layer': 'ocean', paint: { 'fill-color': '#dfeef6' } },
					{ id: 'land', type: 'fill', source: 'osm', 'source-layer': 'land', paint: { 'fill-color': '#f7f4ee' } },
					{ id: 'boundaries', type: 'line', source: 'osm', 'source-layer': 'boundaries', paint: { 'line-color': '#c6c2b9', 'line-width': 1 } }
				]
			},
			center: [-95, 50],
			zoom: 3.6,
			minZoom: 2,
			maxZoom: 8.5,
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

			map.on('click', 'company-circles', (event) => {
				if (!event.features?.length) return;
				const props = event.features[0].properties;
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
		height: 62vh;
		min-height: 460px;
		border-radius: 18px;
		overflow: hidden;
		box-shadow: 0 16px 40px rgba(0, 0, 0, 0.12);
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
