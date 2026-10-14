<script>
  import { onMount } from 'svelte';

  let visible = false;
  let garage = '';
  let kind = 'boat';
  let vehicles = [];
  let selected = null;
  let search = '';
  let filter = 'all';
  let busy = false;
  let timer;

  $: shown = vehicles.filter(v => (filter === 'all' || (filter === 'out' ? v.out : !v.out))
    && `${v.label} ${v.plate} ${v.model}`.toLowerCase().includes(search.toLowerCase()));
  $: current = vehicles.find(v => v.id === selected) || shown[0] || null;

  function post(name, payload = {}) {
    const resource = window.GetParentResourceName?.();
    if (!resource) return Promise.resolve();
    return fetch(`https://${resource}/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    }).catch(() => undefined);
  }

  function close() {
    visible = false;
    busy = false;
    clearTimeout(timer);
    document.body.classList.remove('active');
    post('close');
  }

  function action(type) {
    if (busy || !current) return;
    busy = true;
    post('action', { type, id: current.id });
    clearTimeout(timer);
    timer = setTimeout(() => { busy = false; }, 12000);
  }

  onMount(() => {
    const message = ({ data }) => {
      if (data?.action === 'close') {
        visible = false;
        busy = false;
        document.body.classList.remove('active');
      }
      if (data?.action === 'open') {
        garage = data.garage || 'Garage';
        kind = data.kind === 'boat' ? 'boat' : 'land';
        vehicles = Array.isArray(data.vehicles) ? data.vehicles : [];
        if (!vehicles.some(v => v.id === selected)) selected = vehicles[0]?.id ?? null;
        busy = false;
        clearTimeout(timer);
        visible = true;
        document.body.classList.add('active');
      }
    };
    const keydown = e => { if (e.key === 'Escape' && visible) close(); };
    window.addEventListener('message', message);
    window.addEventListener('keydown', keydown);
    // Browser-only preview. The FiveM NUI stays transparent until opened.
    if (!window.GetParentResourceName && new URLSearchParams(location.search).has('preview')) {
      message({ data: { action: 'open', garage: 'North Yankton Marina', kind: 'boat', vehicles: [
        { id: 1, label: 'The Peregrine', model: 'marquis', plate: 'SM019415', out: false, mounts: 6 },
        { id: 2, label: 'The Wanderer', model: 'dinghy', plate: 'SM903812', out: true, mounts: 2 },
        { id: 3, label: 'The Albatross', model: 'tug', plate: 'SM506331', out: false, mounts: 0 },
      ] } });
    }
    return () => { window.removeEventListener('message', message); window.removeEventListener('keydown', keydown); };
  });
</script>

{#if visible}
  <main class="stage" aria-label="Garage">
    <header class="page-heading">
      <div class="brand"><span class="brand-sigil">✦</span><span>SEAM • HARBOURMASTER</span></div>
      <h1>{kind === 'boat' ? 'Your fleet' : 'Your garage'}</h1>
      <div class="heading-rule"><span>◆</span></div>
    </header>

    <section class="registry parchment">
      <div class="folio"><span>THE HARBOURMASTER’S LEDGER</span><span>NO. 01</span></div>
      <div class="registry-head">
        <div><p class="overline">{garage}</p><h2>{kind === 'boat' ? 'Vessels in your care' : 'Vehicles in your care'}</h2></div>
        <span class="count">{vehicles.length.toString().padStart(2, '0')} REGISTERED</span>
      </div>
      <div class="divider"><span>◆</span></div>
      <div class="toolbar">
        <label class="search"><span>⌕</span><input bind:value={search} placeholder="Search the register..." aria-label="Search vehicles" /></label>
        <div class="filters" aria-label="Filter vehicles">
          <button class:chosen={filter === 'all'} onclick={() => filter = 'all'}>All</button>
          <button class:chosen={filter === 'stored'} onclick={() => filter = 'stored'}>Stored</button>
          <button class:chosen={filter === 'out'} onclick={() => filter = 'out'}>Out</button>
        </div>
      </div>
      <div class="list">
        {#each shown as vehicle (vehicle.id)}
          <button class="vehicle-row" class:selected={current?.id === vehicle.id} onclick={() => selected = vehicle.id}>
            <span class="row-symbol">{kind === 'boat' ? '⚓' : '✦'}</span>
            <span class="vehicle-name"><strong>{vehicle.label}</strong><small>{vehicle.model.toUpperCase()} · {vehicle.plate}</small></span>
            <span class:afloat={vehicle.out} class="status">{vehicle.out ? 'OUT' : 'STORED'}</span>
          </button>
        {:else}
          <div class="empty"><span>◇</span><p>{vehicles.length ? 'No entries match this search.' : 'No vehicles registered yet.'}</p></div>
        {/each}
      </div>
      <footer class="registry-foot">Each registration has its own record.<br />Equipment and cargo stay with this {kind === 'boat' ? 'vessel' : 'vehicle'}.</footer>
    </section>

    <aside class="details parchment">
      {#if current}
        <div class="folio"><span>REGISTRATION CARD</span><span>#{String(current.id).padStart(4, '0')}</span></div>
        <div class="emblem"><span>{kind === 'boat' ? '⚓' : '✦'}</span><div class="emblem-ring"></div></div>
        <p class="overline center">{kind === 'boat' ? 'VESSEL OF THE FLEET' : 'YOUR REGISTERED VEHICLE'}</p>
        <h2 class="detail-title">{current.label}</h2>
        <div class="detail-rule"><span>◆</span></div>
        <dl class="facts">
          <div><dt>Registration</dt><dd>{current.plate}</dd></div>
          <div><dt>Model</dt><dd>{current.model}</dd></div>
          <div><dt>Fitted mounts</dt><dd>{current.mounts ?? 0}</dd></div>
          <div><dt>Current berth</dt><dd>{current.out ? 'At sea / out' : garage}</dd></div>
        </dl>
        <button class="primary" disabled={busy} onclick={() => action(current.out ? 'store' : 'takeOut')}>
          <span>{current.out ? '↧' : '↗'}</span>{busy ? 'UPDATING REGISTER...' : current.out ? 'STORE VEHICLE' : kind === 'boat' ? 'LAUNCH VESSEL' : 'TAKE VEHICLE OUT'}
        </button>
        <p class="detail-help">{current.out ? 'Bring it close to this garage before storing.' : 'The launch space must be clear.'}</p>
      {:else}
        <div class="folio"><span>REGISTRATION CARD</span><span>—</span></div>
        <div class="emblem"><span>⚓</span><div class="emblem-ring"></div></div>
        <h2 class="detail-title">No entry selected</h2>
        <p class="detail-help">Your registered vehicles appear in the ledger.</p>
      {/if}
    </aside>
    <button class="close" aria-label="Close garage" onclick={close}>×</button>
    <div class="control-hint"><kbd>ESC</kbd> Close <span>·</span> Select a registration to see its details</div>
  </main>
{/if}
