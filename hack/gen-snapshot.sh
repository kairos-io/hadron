#!/bin/sh
# Generate per-ref component manifests + an index into docs/static/components/.
set -eu

ROOT="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
OUT="$ROOT/docs/static/components"
GEN="$ROOT/hack/gen-components.sh"
DATE="${SOURCE_DATE_EPOCH:-}"

rm -rf "$OUT"
mkdir -p "$OUT"

# Refs: main first, then every v* tag (version-sorted, newest first)
REFS="main"
TAGS="$(git -C "$ROOT" tag -l 'v*' --sort=-version:refname || true)"

# main snapshot (use current checkout's Dockerfile if HEAD is main)
"$GEN" --ref main --name main --out-dir "$OUT" --format both --date "$DATE" \
  || "$GEN" --ref worktree --name main --out-dir "$OUT" --format both --date "$DATE"

for tag in $TAGS; do
  # Skip (don't abort under set -e) any tag whose manifest can't be generated.
  if "$GEN" --ref "$tag" --name "$tag" --out-dir "$OUT" --format both --date "$DATE"; then
    REFS="$REFS $tag"
  else
    echo "warning: skipping tag $tag (could not generate manifest)" >&2
  fi
done

# index.json
{
  printf '['
  sep=''
  for r in $REFS; do printf '%s"%s"' "$sep" "$r"; sep=', '; done
  printf ']\n'
} > "$OUT/index.json"

# index.html (self-contained, no framework — fetches index.json + <ref>.json at runtime)
cat > "$OUT/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hadron · Component Manifests</title>
<meta name="description" content="Component and version manifest for every Hadron Linux build — kernel and all upstream components, per release.">
<style>
  :root{
    --bg0:#071026; --bg1:#0e2540; --accent:#1baaff; --accent2:#7fd4ff;
    --pop:#ee5007; --text:#eaf2fb; --muted:#9fb3c8;
    --card:rgba(255,255,255,.04); --border:rgba(27,170,255,.18); --border2:rgba(27,170,255,.32);
  }
  *{box-sizing:border-box}
  html,body{margin:0}
  body{
    font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
    color:var(--text); background:linear-gradient(145deg,var(--bg0),var(--bg1)) fixed;
    min-height:100vh; line-height:1.5;
  }
  a{color:var(--accent2); text-decoration:none}
  a:hover{text-decoration:underline}
  .wrap{max-width:1080px; margin:0 auto; padding:2.2rem 1.2rem 4rem}
  header{display:flex; align-items:center; gap:.9rem; margin-bottom:.4rem}
  header img{height:42px; width:auto}
  header .titles h1{font-size:1.5rem; margin:0; font-weight:650; letter-spacing:.2px}
  header .titles p{margin:.15rem 0 0; color:var(--muted); font-size:.92rem}
  .controls{
    position:sticky; top:0; z-index:5; margin:1.4rem 0 1.6rem; padding:.85rem 1rem;
    display:flex; flex-wrap:wrap; align-items:center; gap:.8rem;
    background:rgba(7,16,38,.82); backdrop-filter:blur(8px);
    border:1px solid var(--border); border-radius:12px;
  }
  .controls label{font-size:.8rem; color:var(--muted); text-transform:uppercase; letter-spacing:.6px; margin-right:.1rem}
  select,input[type=search]{
    background:#0a1a33; color:var(--text); border:1px solid var(--border2);
    border-radius:8px; padding:.5rem .7rem; font-size:.95rem; font-family:inherit;
  }
  select:focus,input:focus{outline:2px solid var(--accent); outline-offset:1px}
  input[type=search]{flex:1; min-width:160px}
  .meta{margin-left:auto; display:flex; align-items:center; gap:.9rem; font-size:.85rem; color:var(--muted)}
  .chip{background:rgba(27,170,255,.12); border:1px solid var(--border); color:var(--accent2);
    border-radius:999px; padding:.18rem .6rem; font-size:.78rem; white-space:nowrap}
  .raw a{margin-left:.55rem; font-size:.85rem}
  .grid{display:grid; grid-template-columns:repeat(auto-fill,minmax(300px,1fr)); gap:1rem}
  .group{background:var(--card); border:1px solid var(--border); border-radius:12px; padding:.2rem 0 .4rem; overflow:hidden}
  .group.other{border-color:rgba(238,80,7,.28)}
  .group h2{
    display:flex; align-items:center; justify-content:space-between; gap:.5rem;
    font-size:.82rem; text-transform:uppercase; letter-spacing:.8px; color:var(--accent2);
    margin:0; padding:.75rem 1rem .55rem; border-bottom:1px solid var(--border);
  }
  .group.other h2{color:#ffb27a}
  .group h2 .cnt{font-size:.72rem; color:var(--muted); background:rgba(255,255,255,.05);
    border-radius:999px; padding:.1rem .5rem; letter-spacing:.4px}
  .row{display:flex; align-items:baseline; justify-content:space-between; gap:1rem;
    padding:.34rem 1rem; font-size:.92rem}
  .row:nth-child(even){background:rgba(255,255,255,.018)}
  .row .name{color:var(--text)}
  .row .ver{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:.85rem;
    color:var(--accent); text-align:right; word-break:break-all; max-width:55%}
  .empty{color:var(--muted); padding:2rem 1rem; text-align:center}
  footer{margin-top:2.6rem; color:var(--muted); font-size:.82rem; border-top:1px solid var(--border); padding-top:1.1rem}
  .hide{display:none}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <img src="/images/hadron-logo.svg" alt="Hadron" onerror="this.style.display='none'">
    <div class="titles">
      <h1>Component Manifests</h1>
      <p>The exact upstream component versions shipped in each Hadron build.</p>
    </div>
  </header>

  <div class="controls">
    <label for="ref">Release</label>
    <select id="ref" aria-label="Select a release"></select>
    <input id="filter" type="search" placeholder="Filter components…" aria-label="Filter components" autocomplete="off">
    <div class="meta">
      <span class="chip" id="commit"></span>
      <span class="chip" id="count"></span>
      <span class="raw" id="raw"></span>
    </div>
  </div>

  <div id="content" class="grid"></div>
  <div id="empty" class="empty hide">No components match your filter.</div>

  <footer>
    Generated from the Hadron <code>Dockerfile</code> · machine-readable JSON available per release ·
    <a href="https://github.com/kairos-io/hadron">github.com/kairos-io/hadron</a>
  </footer>
</div>

<script>
(function(){
  var refSel=document.getElementById('ref'), filterEl=document.getElementById('filter'),
      content=document.getElementById('content'), emptyEl=document.getElementById('empty'),
      commitEl=document.getElementById('commit'), countEl=document.getElementById('count'),
      rawEl=document.getElementById('raw');
  var current=null;

  function esc(s){return String(s).replace(/[&<>"]/g,function(c){
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}

  function render(){
    if(!current){return;}
    var q=(filterEl.value||'').trim().toLowerCase();
    var groups=current.groups||{}, names=Object.keys(groups), shown=0, html='';
    names.forEach(function(g){
      var comps=groups[g]||{}, keys=Object.keys(comps);
      var rows=keys.filter(function(k){
        return !q || k.toLowerCase().indexOf(q)>=0 || String(comps[k]).toLowerCase().indexOf(q)>=0;
      });
      if(!rows.length){return;}
      shown+=rows.length;
      var isOther=g.toLowerCase()==='other';
      html+='<section class="group'+(isOther?' other':'')+'">'+
        '<h2>'+esc(g)+'<span class="cnt">'+rows.length+'</span></h2>';
      rows.forEach(function(k){
        html+='<div class="row"><span class="name">'+esc(k)+'</span>'+
              '<span class="ver">'+esc(comps[k])+'</span></div>';
      });
      html+='</section>';
    });
    content.innerHTML=html;
    emptyEl.classList.toggle('hide', shown>0);
  }

  function total(m){var n=0,g=m.groups||{};Object.keys(g).forEach(function(k){n+=Object.keys(g[k]).length;});return n;}

  function load(ref){
    fetch('./'+encodeURIComponent(ref)+'.json',{cache:'no-cache'}).then(function(r){return r.json();}).then(function(m){
      current=m;
      commitEl.textContent=m.commit?('commit '+m.commit):'';
      commitEl.style.display=m.commit?'':'none';
      countEl.textContent=total(m)+' components';
      rawEl.innerHTML='<a href="./'+ref+'.json">json</a><a href="./'+ref+'.md">markdown</a>';
      if(location.hash.slice(1)!==ref){history.replaceState(null,'','#'+ref);}
      render();
    }).catch(function(){content.innerHTML='<div class="empty">Could not load manifest for '+esc(ref)+'.</div>';});
  }

  fetch('./index.json',{cache:'no-cache'}).then(function(r){return r.json();}).then(function(refs){
    refs.forEach(function(ref){
      var o=document.createElement('option'); o.value=ref;
      o.textContent=ref==='main'?'main (latest)':ref; refSel.appendChild(o);
    });
    var want=location.hash.slice(1);
    var start=(want&&refs.indexOf(want)>=0)?want:refs[0];
    refSel.value=start; load(start);
  });

  refSel.addEventListener('change',function(){load(refSel.value);});
  filterEl.addEventListener('input',render);
  window.addEventListener('hashchange',function(){
    var h=location.hash.slice(1);
    if(h && h!==refSel.value){refSel.value=h; load(h);}
  });
})();
</script>
</body>
</html>
HTML
