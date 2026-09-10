.pragma library

// Strict validation applies only to new intents. Untouched legacy values and
// extension keys stay byte-for-value equivalent in the requested snapshot.
function own(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function canonicalApplicationId(value) {
  if (typeof value !== "string") return ""
  var id = value.trim().toLowerCase().replace(/\.desktop$/, "")
  if (!id || id === "unknown-application" || id === "__proto__"
      || id === "constructor" || id === "prototype"
      || /[\x00-\x1f\x7f/\\]/.test(id)) return ""
  return id
}

function valueError(value, spec) {
  if (spec.type === "boolean" && typeof value !== "boolean") return "Expected a boolean"
  if (spec.type === "string") {
    if (typeof value !== "string") return "Expected a string"
    if (spec.minLength && value.trim().length < spec.minLength) return "String must not be empty"
  }
  if (spec.type === "integer" || spec.type === "number") {
    if (typeof value !== "number" || !isFinite(value)) return "Expected a finite number"
    if (spec.type === "integer" && Math.floor(value) !== value) return "Expected an integer"
    if (spec.minimum !== undefined && value < spec.minimum) return "Value is below " + spec.minimum
    if (spec.maximum !== undefined && value > spec.maximum) return "Value is above " + spec.maximum
  }
  if (spec.enum && spec.enum.indexOf(value) < 0) return "Expected one of: " + spec.enum.join(", ")
  if (spec.format === "color" && value !== ""
      && !/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)
      && !/^@[a-z][a-z0-9_.-]*$/.test(value))
    return "Expected empty, #RRGGBB, Qt #AARRGGBB or @theme.token"
  if (spec.type === "array") {
    if (!Array.isArray(value)) return "Expected an array"
    if (spec.format === "application-ids") {
      var seen = Object.create(null)
      for (var i = 0; i < value.length; ++i) {
        var id = canonicalApplicationId(value[i])
        if (!id) return "Invalid application ID at index " + i
        if (own(seen, id)) return "Duplicate application ID: " + value[i]
        seen[id] = true
      }
    }
  }
  if (spec.type === "object" && !isObject(value)) return "Expected an object"
  return ""
}

function validatePatch(patch, schema) {
  var errors = []
  if (!isObject(patch)) return { ok: false, errors: [{ key: "", message: "Patch must be a JSON object" }] }
  var keys = Object.keys(patch)
  for (var i = 0; i < keys.length; ++i) {
    var key = keys[i]
    var error = ""
    if (key === "__proto__" || key === "constructor" || key === "prototype"
        || !own(schema.settings, key)) error = "Unknown or reserved setting"
    else error = valueError(patch[key], schema.settings[key])
    if (error) errors.push({ key: key, message: error })
  }
  return { ok: errors.length === 0, errors: errors }
}

function applyPatch(current, patch, schema) {
  var result = validatePatch(patch, schema)
  result.changedKeys = []
  if (!result.ok) return result
  var updated = Object.create(null)
  Object.keys(current).forEach(function(key) { updated[key] = current[key] })
  Object.keys(patch).forEach(function(key) {
    if (!own(current, key) || JSON.stringify(current[key]) !== JSON.stringify(patch[key]))
      result.changedKeys.push(key)
    updated[key] = patch[key]
  })
  result.settings = updated
  return result
}

function preferenceResetPatch(defaults, schema) {
  var patch = Object.create(null)
  Object.keys(defaults).forEach(function(key) {
    if (own(schema.settings, key) && schema.settings[key].resetWithPreferences !== false)
      patch[key] = defaults[key]
  })
  return patch
}
