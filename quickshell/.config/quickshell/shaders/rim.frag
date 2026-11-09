#version 440
// «Жидкое стекло»: оптика капли, а не мутная плёнка.
//   слой 5 — фаска: тонкая грань; яркая у источника света, почти исчезает сбоку (глаз достраивает изгиб),
//            на противоположной стороне — вторичный рефлекс. Источник света следует за курсором.
//   слой 3 — толща (Френель): центр прозрачен, плотность растёт к краю.
//   слой 4 — мениск: мягкое свечение внутри контура, сильнее со стороны света.
//   хроматика: циан слева, маджента справа — едва заметно, у самой грани.
//   плюс: пятно света под курсором, пробегающий блик при наведении, вспышка при нажатии.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    float rimWidth;
    vec4 rimColor;
    vec4 glintColor;
    float angle;
    float hover;
    vec2 mouse;
    float shine;
    float press;
    float fresnel;      // сила эффекта толщи и мениска (0 — только фаска)
};

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 p = px - size * 0.5;
    vec2 b = size * 0.5;
    float r = min(radius, min(b.x, b.y));
    float d = sdRoundBox(p, b, r);
    float inside = max(-d, 0.0);                       // глубина от края внутрь, px
    float body = clamp(0.5 - d, 0.0, 1.0);             // 1 внутри контура

    // направление точки грани относительно центра (с поправкой на вытянутость)
    vec2 n = p / max(b, vec2(1.0));
    float th = atan(n.y, n.x);
    float l1 = max(cos(th - angle), 0.0);              // сторона источника
    float l2 = max(cos(th - angle - 3.14159265), 0.0); // противоположная
    float spec = pow(l1, 5.0) + 0.55 * pow(l2, 7.0);

    // курсор
    float md = length(px - mouse);
    float spot = hover * exp(-md * md / (2.0 * 55.0 * 55.0));
    float glow = hover * exp(-md * md / (2.0 * 90.0 * 90.0));

    // пробегающий блик
    float sweep = 0.0;
    if (shine >= 0.0) {
        float diag = (px.x + px.y * 0.6) / (size.x + size.y * 0.6);
        float x = diag - (shine * 1.6 - 0.3);
        sweep = exp(-x * x / (2.0 * 0.05 * 0.05));
    }

    // ── фаска: у света толще и ярче; сбоку растворяется (≈0.3 от базового)
    float lit = clamp(spec * 0.9 + spot * 1.4 + sweep + press * 0.5, 0.0, 1.0);
    float w = rimWidth * (1.0 + spot * 0.9 + sweep * 0.6 + press * 0.4 + spec * 0.5);
    float ring = clamp(0.5 - (abs(d + w * 0.5) - w * 0.5), 0.0, 1.0);
    vec4 c = mix(rimColor, glintColor, lit);
    float vis = clamp(0.30 + 0.70 * lit, 0.0, 1.0);
    vec4 rim = vec4(c.rgb * c.a, c.a) * (ring * vis);

    // ── толща: плотность к краю (Френель), центр почти пуст
    float edge = exp(-inside / 4.5);                 // только у самой грани, центр — чистый
    float fa = fresnel * edge * 0.055 * body;
    vec4 fill = vec4(vec3(fa), fa);

    // ── мениск: внутренняя подушка у самой грани, ярче со стороны света
    float men = fresnel * exp(-inside / 3.5) * (0.02 + 0.10 * (l1 * l1) + 0.03 * l2) * body;
    men *= 1.0 + glow * 0.8 + press * 0.6;
    vec3 mc = mix(vec3(1.0), glintColor.rgb, 0.35);
    vec4 meniscus = vec4(mc * men, men);

    // ── свечение под курсором и отблеск пробега
    float ga = glintColor.a * body * (glow * 0.14 + sweep * 0.06 + press * 0.07) * clamp(inside / 6.0, 0.0, 1.0);
    vec4 hoverFill = vec4(glintColor.rgb * ga, ga);

    // ── хроматическая кайма: тонкий слой чуть глубже грани, по бокам
    float ringC = clamp(0.5 - (abs(d + 2.4) - 0.8), 0.0, 1.0);
    float side = clamp(abs(n.x) * 1.4 - 0.2, 0.0, 1.0);
    vec3 cc = n.x < 0.0 ? vec3(0.0, 1.0, 1.0) : vec3(1.0, 0.0, 0.55);
    float ca = 0.09 * fresnel * side * ringC;
    vec4 chroma = vec4(cc * ca, ca);

    vec4 glass = fill + meniscus + hoverFill + chroma;
    fragColor = (rim + glass * (1.0 - rim.a)) * qt_Opacity;
}
