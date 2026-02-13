const PLUGIN_DATA_KEY_ID = "uiSchemaId";
const PLUGIN_DATA_KEY_MANAGED = "uiSchemaManaged";

const CREATE_SUPPORTED_TYPES = new Set([
  "FRAME",
  "GROUP",
  "COMPONENT",
  "SECTION",
  "RECTANGLE",
  "ELLIPSE",
  "LINE",
  "POLYGON",
  "STAR",
  "VECTOR",
  "TEXT",
  "SLICE",
  "INSTANCE",
  "BUTTON"
]);

const GRADIENT_TYPES = new Set([
  "GRADIENT_LINEAR",
  "GRADIENT_RADIAL",
  "GRADIENT_ANGULAR",
  "GRADIENT_DIAMOND"
]);

figma.showUI(__html__, { width: 460, height: 680 });

function post(type, payload) {
  figma.ui.postMessage({ type, payload });
}

function toNumber(value, fallback) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function canonicalType(type) {
  if (type === "BUTTON") return "FRAME";
  return type;
}

function safeSet(node, key, value) {
  if (value === undefined) return;
  if (!(key in node)) return;
  try {
    node[key] = value;
  } catch (_) {
    // ignore unsupported property writes on specific node types.
  }
}

function safeGet(node, key, fallback) {
  try {
    if (key in node) return node[key];
  } catch (_) {
    // noop
  }
  return fallback;
}

function hasChildren(node) {
  return "children" in node && typeof node.appendChild === "function" && node.type !== "INSTANCE";
}

function isManaged(node) {
  return node.getPluginData(PLUGIN_DATA_KEY_MANAGED) === "1";
}

function hexToRgb(hex) {
  if (typeof hex !== "string") return null;
  const cleaned = hex.replace("#", "").trim();
  if (!(cleaned.length === 6 || cleaned.length === 8)) return null;
  const base = cleaned.slice(0, 6);
  const alpha = cleaned.length === 8 ? cleaned.slice(6) : null;
  const num = Number.parseInt(base, 16);
  if (Number.isNaN(num)) return null;
  const r = ((num >> 16) & 255) / 255;
  const g = ((num >> 8) & 255) / 255;
  const b = (num & 255) / 255;
  const a = alpha ? Number.parseInt(alpha, 16) / 255 : 1;
  return { r, g, b, a };
}

function normalizeRgbObject(value) {
  if (!value || typeof value !== "object") return null;
  if (!["r", "g", "b"].every((k) => typeof value[k] === "number")) return null;

  const factor = value.r > 1 || value.g > 1 || value.b > 1 ? 255 : 1;
  const r = Math.max(0, Math.min(1, value.r / factor));
  const g = Math.max(0, Math.min(1, value.g / factor));
  const b = Math.max(0, Math.min(1, value.b / factor));
  const a = typeof value.a === "number" ? Math.max(0, Math.min(1, value.a)) : 1;
  return { r, g, b, a };
}

function normalizeColorInput(value) {
  if (typeof value === "string") return hexToRgb(value);
  return normalizeRgbObject(value);
}

function toSolidPaint(colorInput, defaultOpacity) {
  const c = normalizeColorInput(colorInput);
  if (!c) return null;
  return {
    type: "SOLID",
    color: { r: c.r, g: c.g, b: c.b },
    opacity: typeof defaultOpacity === "number" ? defaultOpacity : c.a
  };
}

function base64ToBytes(base64) {
  const cleaned = String(base64 || "").replace(/\\s+/g, "");
  if (typeof atob === "function") {
    const binary = atob(cleaned);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const lookup = new Uint8Array(256);
  lookup.fill(255);
  for (let i = 0; i < chars.length; i += 1) lookup[chars.charCodeAt(i)] = i;

  const output = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < cleaned.length; i += 1) {
    const ch = cleaned.charCodeAt(i);
    if (cleaned[i] === "=") break;
    const value = lookup[ch];
    if (value === 255) continue;
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output.push((buffer >> bits) & 0xff);
    }
  }
  return new Uint8Array(output);
}

async function imageHashFromPaintDef(paintDef) {
  if (paintDef.imageHash) return paintDef.imageHash;

  if (typeof paintDef.imageBytesBase64 === "string") {
    const bytes = base64ToBytes(paintDef.imageBytesBase64);
    return figma.createImage(bytes).hash;
  }

  if (typeof paintDef.imageUrl === "string" && paintDef.imageUrl.trim() !== "") {
    const response = await fetch(paintDef.imageUrl);
    if (!response.ok) throw new Error(`无法下载图片: ${paintDef.imageUrl}`);
    const buffer = await response.arrayBuffer();
    return figma.createImage(new Uint8Array(buffer)).hash;
  }

  return null;
}

function normalizeGradientStops(stops) {
  if (!Array.isArray(stops) || stops.length === 0) return null;
  const normalized = [];
  for (const stop of stops) {
    if (!stop || typeof stop !== "object") continue;
    const color = normalizeColorInput(stop.color);
    if (!color) continue;
    normalized.push({
      position: toNumber(stop.position, 0),
      color: { r: color.r, g: color.g, b: color.b, a: toNumber(stop.opacity, color.a) }
    });
  }
  return normalized.length > 0 ? normalized : null;
}

async function normalizePaint(paintDef) {
  if (typeof paintDef === "string") {
    return toSolidPaint(paintDef);
  }

  if (!paintDef || typeof paintDef !== "object") return null;

  const type = paintDef.type || "SOLID";

  if (type === "SOLID") {
    if (paintDef.color && typeof paintDef.color === "object" && "r" in paintDef.color) {
      const color = normalizeRgbObject(paintDef.color);
      if (!color) return null;
      return {
        type: "SOLID",
        color: { r: color.r, g: color.g, b: color.b },
        opacity: toNumber(paintDef.opacity, color.a)
      };
    }
    return toSolidPaint(paintDef.color || paintDef.hex || paintDef.value, paintDef.opacity);
  }

  if (GRADIENT_TYPES.has(type)) {
    const gradientStops = normalizeGradientStops(paintDef.gradientStops);
    if (!gradientStops) return null;
    return {
      type,
      gradientStops,
      gradientTransform: Array.isArray(paintDef.gradientTransform)
        ? paintDef.gradientTransform
        : [
            [1, 0, 0],
            [0, 1, 0]
          ],
      opacity: typeof paintDef.opacity === "number" ? paintDef.opacity : 1
    };
  }

  if (type === "IMAGE") {
    const imageHash = await imageHashFromPaintDef(paintDef);
    if (!imageHash) return null;
    return {
      type: "IMAGE",
      imageHash,
      scaleMode: paintDef.scaleMode || "FILL",
      opacity: typeof paintDef.opacity === "number" ? paintDef.opacity : 1,
      imageTransform: Array.isArray(paintDef.imageTransform) ? paintDef.imageTransform : undefined,
      rotation: typeof paintDef.rotation === "number" ? paintDef.rotation : undefined,
      scalingFactor: typeof paintDef.scalingFactor === "number" ? paintDef.scalingFactor : undefined
    };
  }

  if (paintDef.color) {
    return toSolidPaint(paintDef.color, paintDef.opacity);
  }

  return null;
}

async function normalizePaintList(defs) {
  const result = [];
  for (const def of asArray(defs)) {
    const paint = await normalizePaint(def);
    if (paint) result.push(paint);
  }
  return result;
}

function normalizeEffect(effectDef) {
  if (!effectDef || typeof effectDef !== "object") return null;
  const type = effectDef.type;
  if (!type) return null;

  if (type === "LAYER_BLUR" || type === "BACKGROUND_BLUR") {
    return {
      type,
      radius: toNumber(effectDef.radius, 0),
      visible: effectDef.visible !== false
    };
  }

  if (type === "DROP_SHADOW" || type === "INNER_SHADOW") {
    const color = normalizeColorInput(effectDef.color || "#00000066") || { r: 0, g: 0, b: 0, a: 0.4 };
    return {
      type,
      color: { r: color.r, g: color.g, b: color.b, a: color.a },
      offset: {
        x: toNumber(effectDef.offset?.x, 0),
        y: toNumber(effectDef.offset?.y, 0)
      },
      radius: toNumber(effectDef.radius, 0),
      spread: toNumber(effectDef.spread, 0),
      blendMode: effectDef.blendMode || "NORMAL",
      visible: effectDef.visible !== false
    };
  }

  return null;
}

function normalizeEffects(effectDefs) {
  const effects = [];
  for (const def of asArray(effectDefs)) {
    const effect = normalizeEffect(def);
    if (effect) effects.push(effect);
  }
  return effects;
}

function buildIdIndex() {
  const map = new Map();
  const nodes = figma.currentPage.findAll((node) => node.getPluginData(PLUGIN_DATA_KEY_ID) !== "");
  for (const node of nodes) {
    const id = node.getPluginData(PLUGIN_DATA_KEY_ID);
    if (id) map.set(id, node);
  }
  return map;
}

function schemaRoots(schema) {
  if (Array.isArray(schema.frames) && schema.frames.length > 0) return schema.frames;
  if (Array.isArray(schema.nodes) && schema.nodes.length > 0) return schema.nodes;
  return [];
}

function validateSchema(schema) {
  const errors = [];

  if (!schema || typeof schema !== "object") {
    errors.push("schema 必须是对象");
    return errors;
  }
  if (schema.version !== "1.0") {
    errors.push('schema.version 必须为 "1.0"');
  }

  const roots = schemaRoots(schema);
  if (roots.length === 0) {
    errors.push("schema.frames 或 schema.nodes 必须是非空数组");
    return errors;
  }

  const ids = new Set();

  function walk(node, path) {
    if (!node || typeof node !== "object") {
      errors.push(`${path} 必须是对象`);
      return;
    }

    if (typeof node.id !== "string" || node.id.trim() === "") {
      errors.push(`${path}.id 必须是非空字符串`);
    } else if (ids.has(node.id)) {
      errors.push(`重复 id: ${node.id}`);
    } else {
      ids.add(node.id);
    }

    if (typeof node.name !== "string" || node.name.trim() === "") {
      errors.push(`${path}.name 必须是非空字符串`);
    }

    if (typeof node.type !== "string" || !CREATE_SUPPORTED_TYPES.has(node.type)) {
      errors.push(`${path}.type 不支持: ${node.type}`);
    }

    if (!node.size || !Number.isFinite(node.size.width) || !Number.isFinite(node.size.height)) {
      errors.push(`${path}.size.width/height 必须是数字`);
    }

    if (node.type === "INSTANCE" && !node.componentId && !node.componentKey) {
      errors.push(`${path} (INSTANCE) 需要 componentId 或 componentKey`);
    }

    if (node.children !== undefined && !Array.isArray(node.children)) {
      errors.push(`${path}.children 必须是数组`);
    }

    asArray(node.children).forEach((child, idx) => walk(child, `${path}.children[${idx}]`));
  }

  roots.forEach((root, idx) => walk(root, `roots[${idx}]`));
  return errors;
}

async function loadFontForText(def) {
  if (def.fontName && typeof def.fontName === "object") {
    try {
      await figma.loadFontAsync(def.fontName);
      return def.fontName;
    } catch (_) {
      // fallback below
    }
  }

  const family = def.fontFamily || "Inter";
  let style = def.fontStyle || "Regular";
  if (!def.fontStyle && typeof def.fontWeight === "number") {
    if (def.fontWeight >= 700) style = "Bold";
    else if (def.fontWeight >= 600) style = "Semi Bold";
    else if (def.fontWeight >= 500) style = "Medium";
  }

  const preferred = { family, style };
  try {
    await figma.loadFontAsync(preferred);
    return preferred;
  } catch (_) {
    const fallback = { family: "Inter", style: "Regular" };
    await figma.loadFontAsync(fallback);
    return fallback;
  }
}

function applyGeometry(node, def) {
  if (def.position) {
    safeSet(node, "x", toNumber(def.position.x, safeGet(node, "x", 0)));
    safeSet(node, "y", toNumber(def.position.y, safeGet(node, "y", 0)));
  }

  if (def.size) {
    const w = Math.max(1, toNumber(def.size.width, safeGet(node, "width", 1)));
    const h = Math.max(1, toNumber(def.size.height, safeGet(node, "height", 1)));
    try {
      if (typeof node.resizeWithoutConstraints === "function") {
        node.resizeWithoutConstraints(w, h);
      } else if (typeof node.resize === "function") {
        node.resize(w, h);
      }
    } catch (_) {
      // Some nodes have locked dimensions.
    }
  }

  if (typeof def.rotation === "number") safeSet(node, "rotation", def.rotation);
  if (typeof def.isMask === "boolean") safeSet(node, "isMask", def.isMask);
}

function applyLayoutSelf(node, def) {
  const ls = def.layoutSelf;
  if (!ls || typeof ls !== "object") return;
  safeSet(node, "layoutAlign", ls.layoutAlign);
  safeSet(node, "layoutGrow", ls.layoutGrow);
  safeSet(node, "layoutPositioning", ls.layoutPositioning);
  safeSet(node, "minWidth", ls.minWidth);
  safeSet(node, "maxWidth", ls.maxWidth);
  safeSet(node, "minHeight", ls.minHeight);
  safeSet(node, "maxHeight", ls.maxHeight);
  safeSet(node, "strokesIncludedInLayout", ls.strokesIncludedInLayout);
}

function applyAutoLayout(node, def) {
  if (!("layoutMode" in node)) return;
  const layout = def.layout || {};
  const mode = layout.mode || safeGet(node, "layoutMode", "NONE");
  safeSet(node, "layoutMode", mode);

  if (mode === "HORIZONTAL" || mode === "VERTICAL") {
    safeSet(node, "primaryAxisSizingMode", layout.primaryAxisSizingMode || "FIXED");
    safeSet(node, "counterAxisSizingMode", layout.counterAxisSizingMode || "FIXED");
    safeSet(node, "primaryAxisAlignItems", layout.primaryAxisAlignItems || "MIN");
    safeSet(node, "counterAxisAlignItems", layout.counterAxisAlignItems || "MIN");
    safeSet(node, "itemSpacing", toNumber(layout.itemSpacing, safeGet(node, "itemSpacing", 0)));
    safeSet(node, "paddingLeft", toNumber(layout.paddingLeft, safeGet(node, "paddingLeft", 0)));
    safeSet(node, "paddingRight", toNumber(layout.paddingRight, safeGet(node, "paddingRight", 0)));
    safeSet(node, "paddingTop", toNumber(layout.paddingTop, safeGet(node, "paddingTop", 0)));
    safeSet(node, "paddingBottom", toNumber(layout.paddingBottom, safeGet(node, "paddingBottom", 0)));
    safeSet(node, "layoutWrap", layout.layoutWrap || safeGet(node, "layoutWrap", "NO_WRAP"));
    safeSet(node, "counterAxisSpacing", toNumber(layout.counterAxisSpacing, safeGet(node, "counterAxisSpacing", 0)));
  }

  applyLayoutSelf(node, def);
}

function applyCornersAndStroke(node, def) {
  if (typeof def.cornerRadius === "number") safeSet(node, "cornerRadius", def.cornerRadius);
  safeSet(node, "topLeftRadius", def.topLeftRadius);
  safeSet(node, "topRightRadius", def.topRightRadius);
  safeSet(node, "bottomLeftRadius", def.bottomLeftRadius);
  safeSet(node, "bottomRightRadius", def.bottomRightRadius);

  safeSet(node, "strokeWeight", def.strokeWeight);
  safeSet(node, "strokeAlign", def.strokeAlign);
  safeSet(node, "strokeCap", def.strokeCap);
  safeSet(node, "strokeJoin", def.strokeJoin);
  safeSet(node, "dashPattern", Array.isArray(def.dashPattern) ? def.dashPattern : undefined);
  safeSet(node, "miterLimit", def.miterLimit);
}

function applyCommonPrimitive(node, def) {
  node.name = def.name || node.name;
  node.visible = def.visible !== false;
  node.locked = def.locked === true;

  if (typeof def.opacity === "number") safeSet(node, "opacity", def.opacity);
  safeSet(node, "blendMode", def.blendMode);
  safeSet(node, "clipsContent", def.clipsContent);
  safeSet(node, "expanded", def.expanded);
  safeSet(node, "exportSettings", Array.isArray(def.exportSettings) ? def.exportSettings : undefined);

  if (def.constraints && typeof def.constraints === "object") {
    safeSet(node, "constraints", def.constraints);
  }

  applyCornersAndStroke(node, def);
}

async function applyPaintAndEffects(node, def) {
  if (def.fills && "fills" in node) {
    const fills = await normalizePaintList(def.fills);
    if (fills.length > 0) safeSet(node, "fills", fills);
  }
  if (def.strokes && "strokes" in node) {
    const strokes = await normalizePaintList(def.strokes);
    safeSet(node, "strokes", strokes);
  }
  if (def.effects && "effects" in node) {
    const effects = normalizeEffects(def.effects);
    safeSet(node, "effects", effects);
  }
}

async function applyText(textNode, def) {
  const fontName = await loadFontForText(def);
  safeSet(textNode, "fontName", fontName);

  if (typeof def.characters === "string") {
    textNode.characters = def.characters;
  }

  safeSet(textNode, "fontSize", def.fontSize);
  safeSet(textNode, "textAlignHorizontal", def.textAlignHorizontal);
  safeSet(textNode, "textAlignVertical", def.textAlignVertical);
  safeSet(textNode, "textAutoResize", def.textAutoResize);
  safeSet(textNode, "textCase", def.textCase);
  safeSet(textNode, "textDecoration", def.textDecoration);
  safeSet(textNode, "paragraphSpacing", def.paragraphSpacing);
  safeSet(textNode, "paragraphIndent", def.paragraphIndent);

  if (typeof def.lineHeightPx === "number") {
    safeSet(textNode, "lineHeight", { value: def.lineHeightPx, unit: "PIXELS" });
  } else if (def.lineHeight && typeof def.lineHeight === "object") {
    safeSet(textNode, "lineHeight", def.lineHeight);
  }

  if (def.letterSpacing && typeof def.letterSpacing === "object") {
    safeSet(textNode, "letterSpacing", def.letterSpacing);
  }

  if (def.textFills && Array.isArray(def.textFills)) {
    const fills = await normalizePaintList(def.textFills);
    if (fills.length > 0) safeSet(textNode, "fills", fills);
  }
}

async function createInstanceNode(def) {
  if (def.componentId) {
    const componentNode = figma.getNodeById(def.componentId);
    if (componentNode && typeof componentNode.createInstance === "function") {
      return componentNode.createInstance();
    }
    throw new Error(`INSTANCE 组件不存在或不可实例化: ${def.componentId}`);
  }

  if (def.componentKey) {
    const component = await figma.importComponentByKeyAsync(def.componentKey);
    return component.createInstance();
  }

  throw new Error("INSTANCE 需要 componentId 或 componentKey");
}

async function createNodeByType(def, parent, warnings) {
  switch (def.type) {
    case "FRAME":
      return figma.createFrame();
    case "GROUP": {
      const rect = figma.createRectangle();
      rect.resize(toNumber(def.size?.width, 100), toNumber(def.size?.height, 100));
      rect.opacity = 0;
      parent.appendChild(rect);
      const group = figma.group([rect], parent);
      return group;
    }
    case "COMPONENT":
      return figma.createComponent();
    case "SECTION":
      return figma.createSection();
    case "RECTANGLE":
      return figma.createRectangle();
    case "ELLIPSE":
      return figma.createEllipse();
    case "LINE":
      return figma.createLine();
    case "POLYGON":
      return figma.createPolygon();
    case "STAR":
      return figma.createStar();
    case "VECTOR":
      return figma.createVector();
    case "TEXT":
      return figma.createText();
    case "SLICE":
      return figma.createSlice();
    case "INSTANCE":
      return createInstanceNode(def);
    case "BUTTON":
      return figma.createFrame();
    default:
      warnings.push(`不支持创建的类型: ${def.type}`);
      return figma.createFrame();
  }
}

function ensureParent(node, parent, indexInParent) {
  if (node.parent !== parent && hasChildren(parent)) {
    parent.appendChild(node);
  }
  if (typeof indexInParent === "number" && hasChildren(parent)) {
    const currentIndex = parent.children.indexOf(node);
    if (currentIndex !== indexInParent) {
      parent.insertChild(indexInParent, node);
    }
  }
}

function nodeMatchesType(node, defType) {
  if (defType === "BUTTON") return node.type === "FRAME";
  if (defType === "INSTANCE") return node.type === "INSTANCE";
  return node.type === canonicalType(defType);
}

async function upsertNode(def, parent, idIndex, touched, options, warnings) {
  let node = idIndex.get(def.id);

  if (node && !nodeMatchesType(node, def.type)) {
    if (isManaged(node)) {
      const replacement = await createNodeByType(def, parent, warnings);
      replacement.setPluginData(PLUGIN_DATA_KEY_ID, def.id);
      replacement.setPluginData(PLUGIN_DATA_KEY_MANAGED, "1");
      ensureParent(replacement, parent, options.indexInParent);
      node.remove();
      idIndex.set(def.id, replacement);
      node = replacement;
    } else {
      warnings.push(`节点 ${def.id} 类型不匹配（现有: ${node.type}, 期望: ${def.type}），已保留现有节点。`);
    }
  }

  if (!node) {
    node = await createNodeByType(def, parent, warnings);
    idIndex.set(def.id, node);
  }

  node.setPluginData(PLUGIN_DATA_KEY_ID, def.id);
  node.setPluginData(PLUGIN_DATA_KEY_MANAGED, "1");
  touched.add(def.id);

  ensureParent(node, parent, options.indexInParent);

  if (def.type === "BUTTON") {
    def.layout = {
      ...(def.layout || {}),
      mode: "HORIZONTAL",
      primaryAxisAlignItems: "CENTER",
      counterAxisAlignItems: "CENTER",
      primaryAxisSizingMode: "FIXED",
      counterAxisSizingMode: "FIXED"
    };
  }

  applyGeometry(node, def);
  applyCommonPrimitive(node, def);
  await applyPaintAndEffects(node, def);
  applyAutoLayout(node, def);

  if (def.type === "TEXT" && node.type === "TEXT") {
    await applyText(node, def);
  }

  if (def.type === "BUTTON") {
    const labelDef = {
      id: `${def.id}__label`,
      name: `${def.name}-label`,
      type: "TEXT",
      position: { x: 0, y: 0 },
      size: {
        width: toNumber(def.size?.width, 120),
        height: toNumber(def.size?.height, 20)
      },
      characters: def.characters || def.label || "Button",
      fontFamily: def.fontFamily || "Inter",
      fontStyle: def.fontStyle || "Medium",
      fontWeight: def.fontWeight || 500,
      fontSize: toNumber(def.fontSize, 16),
      textAlignHorizontal: "CENTER",
      textAlignVertical: "CENTER",
      textFills: def.textFills || ["#FFFFFF"]
    };

    await upsertNode(labelDef, node, idIndex, touched, { ...options, indexInParent: 0 }, warnings);
  } else if (Array.isArray(def.children) && hasChildren(node)) {
    for (let i = 0; i < def.children.length; i += 1) {
      await upsertNode(def.children[i], node, idIndex, touched, {
        indexInParent: i,
        pruneMissing: options.pruneMissing
      }, warnings);
    }
  }

  if (options.pruneMissing && hasChildren(node)) {
    const shouldKeep = new Set(asArray(def.children).map((child) => child.id));
    if (def.type === "BUTTON") shouldKeep.add(`${def.id}__label`);

    for (const child of [...node.children]) {
      const childId = child.getPluginData(PLUGIN_DATA_KEY_ID);
      if (isManaged(child) && childId && !shouldKeep.has(childId)) {
        child.remove();
        idIndex.delete(childId);
      }
    }
  }

  return node;
}

function pruneDetached(idIndex, touched) {
  for (const [id, node] of idIndex.entries()) {
    if (!touched.has(id) && isManaged(node)) {
      node.remove();
      idIndex.delete(id);
    }
  }
}

async function applySchema(schema, options) {
  const roots = schemaRoots(schema);
  const idIndex = buildIdIndex();
  const touched = new Set();
  const warnings = [];

  const selected = [];
  for (let i = 0; i < roots.length; i += 1) {
    const root = roots[i];
    const node = await upsertNode(root, figma.currentPage, idIndex, touched, {
      indexInParent: i,
      pruneMissing: options.pruneMissing
    }, warnings);
    selected.push(node);
  }

  if (options.pruneMissing) {
    pruneDetached(idIndex, touched);
  }

  figma.currentPage.selection = selected;
  if (selected.length > 0) {
    figma.viewport.scrollAndZoomIntoView(selected);
  }

  return { selectedCount: selected.length, warnings };
}

figma.ui.onmessage = async (msg) => {
  if (!msg || typeof msg !== "object") return;

  if (msg.type === "validate") {
    try {
      const schema = JSON.parse(msg.payload || "{}");
      const errors = validateSchema(schema);
      post("validated", { ok: errors.length === 0, errors });
    } catch (error) {
      post("validated", { ok: false, errors: [String(error.message || error)] });
    }
    return;
  }

  if (msg.type === "apply") {
    try {
      const schema = JSON.parse(msg.payload || "{}");
      const errors = validateSchema(schema);
      if (errors.length > 0) {
        post("applied", { ok: false, message: "schema 校验失败", errors });
        return;
      }

      const result = await applySchema(schema, { pruneMissing: msg.pruneMissing === true });
      const warningText = result.warnings.length > 0 ? `\n警告:\n- ${result.warnings.join("\n- ")}` : "";
      post("applied", {
        ok: true,
        message: `已同步 ${result.selectedCount} 个顶层节点到当前页面${warningText}`
      });
    } catch (error) {
      post("applied", { ok: false, message: String(error.message || error), errors: [] });
    }
    return;
  }

  if (msg.type === "close") {
    figma.closePlugin("Tsugie UI Schema Bridge 结束");
  }
};
