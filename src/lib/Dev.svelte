<script>
    let showPopup = true;

    function dismissPopup() {
        showPopup = false;
    }

    const now = new Date();
    const dateTimeStr = now.toLocaleString('en-US', {
        weekday: 'short',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: true
    });

</script>

{#if showPopup}
<div class="overlay">
    <div class="popup-box">
        <h3>The page is under development – last updated <span class="datetime">{dateTimeStr}</span></h3>
        <p>Notable updates: titles fixed</p>
        <button on:click={dismissPopup}>OK</button>
    </div>
</div>
{/if}


<style>

    .overlay {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(255, 255, 255, 0.5);
        backdrop-filter: blur(4px);
        z-index: 9999;
        display: flex;
        justify-content: center;
        align-items: center;
    }

    .popup-box {
        background: black;
        padding: 2.5rem 3rem;
        border-radius: 12px;
        box-shadow: 0 0 10px rgba(0, 0, 0, 0.2);
        text-align: center;
        max-width: 440px;
    }

    .popup-box h3 {
        font-family: TradeGothicBold, sans-serif;
        font-weight: normal;
        font-size: 20px;
        color: var(--brandMedBlue, #1a2a4a);
        margin-bottom: 0.5rem;
        line-height: 1.4;
    }

    .popup-box .datetime {
        font-weight: bold;
        color: var(--brandLightBlue, #3a6b8a);
        display: inline-block;
        margin-top: 4px;
    }

    .popup-box p {
        font-family: sans-serif;
        font-size: 16px;
        color: white;
        margin-bottom: 1.8rem;
    }

    .popup-box button {
        padding: 0.6rem 2.8rem;
        background-color: var(--brandDarkBlue, #1a2a4a);
        color: white;
        border: none;
        border-radius: 6px;
        font-size: 16px;
        cursor: pointer;
        transition: background-color 0.2s;
        font-weight: 600;
    }

    .popup-box button:hover {
        background-color: var(--brandLightBlue, #4a7a9c);
    }

    .page-content {
        padding: 2rem;
        font-family: sans-serif;
    }

    .page-content h1 {
        color: var(--brandDarkBlue, #1a2a4a);
    }

</style>
