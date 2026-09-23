.pragma library

var panels = ({})

function register(screenName, panel) {
  if (screenName && panel) {
    panels[screenName] = panel
  }
}

function unregister(screenName, panel) {
  if (screenName && panels[screenName] === panel) {
    delete panels[screenName]
  }
}

function getPanel(screenName) {
  if (screenName && panels[screenName]) return panels[screenName]
  return null
}

function resolveTargetPanel(monitorName, fallbackScreenName) {
  var mon = String(monitorName || "").trim().toLowerCase()
  if (mon) {
    for (var key in panels) {
      if (key.toLowerCase() === mon || key.toLowerCase().indexOf(mon) !== -1) {
        return panels[key]
      }
    }
  }

  // If a panel is already open, target that one (e.g. for toggle/close)
  for (var k in panels) {
    if (panels[k] && panels[k].opened) return panels[k]
  }

  // Otherwise target fallback/focused monitor
  var fallback = String(fallbackScreenName || "").trim()
  if (fallback && panels[fallback]) return panels[fallback]

  // Fallback to any registered panel
  var keys = Object.keys(panels)
  if (keys.length > 0) return panels[keys[0]]

  return null
}

function toggle(monitorName, fallbackScreenName) {
  var p = resolveTargetPanel(monitorName, fallbackScreenName)
  if (p && typeof p.toggle === "function") p.toggle()
}

function open(monitorName, fallbackScreenName) {
  var p = resolveTargetPanel(monitorName, fallbackScreenName)
  if (p && typeof p.open === "function") p.open()
}

function close(monitorName, fallbackScreenName) {
  var p = resolveTargetPanel(monitorName, fallbackScreenName)
  if (p && typeof p.close === "function") p.close()
}
