import React from 'react';
import { StyleSheet } from 'react-native';
import {
  Canvas,
  Circle,
  Group,
  Path,
  Rect,
  Skia,
  Text,
  useFonts,
} from '@shopify/react-native-skia';
import { GAME, COLORS, WAVES } from '../game/config';
import type { Enemy, Player, Projectile } from '../game/types';

interface Props {
  player: Player;
  enemies: Enemy[];
  projectiles: Projectile[];
  elapsed: number;
}

// ============ 场景元素 ============

// 铅笔远山
function PencilMountains() {
  return (
    <Group opacity={0.35}>
      {/* 远山（淡） */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(0, 420);
          p.lineTo(80, 310);
          p.lineTo(140, 380);
          p.lineTo(200, 280);
          p.lineTo(280, 360);
          p.lineTo(340, 300);
          p.lineTo(390, 370);
          p.lineTo(390, 420);
          p.close();
          return p;
        })()}
        color={COLORS.pencilFaint}
      />
      {/* 近山（深） */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(0, 480);
          p.lineTo(60, 400);
          p.lineTo(120, 450);
          p.lineTo(180, 370);
          p.lineTo(250, 430);
          p.lineTo(310, 390);
          p.lineTo(390, 460);
          p.lineTo(390, 480);
          p.close();
          return p;
        })()}
        color={COLORS.pencilLight}
      />
      {/* 山脊线 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(60, 400); p.lineTo(55, 410);
          p.moveTo(180, 370); p.lineTo(175, 385);
          p.moveTo(310, 390); p.lineTo(305, 405);
          return p;
        })()}
        strokeWidth={1}
        style="stroke"
        color={COLORS.pencil}
        opacity={0.4}
      />
    </Group>
  );
}

// 中景草丛和石头
function GrassAndRocks() {
  return (
    <Group>
      {/* 草丛 */}
      {[
        { x: 30, y: 560, s: 1 },
        { x: 70, y: 580, s: 0.8 },
        { x: 320, y: 555, s: 1.1 },
        { x: 360, y: 575, s: 0.7 },
        { x: 150, y: 590, s: 0.6 },
        { x: 260, y: 585, s: 0.9 },
      ].map((g, i) => (
        <Group key={i} transform={[{ translate: [g.x, g.y] }, { scale: g.s }]}>
          <Path
            path={(() => {
              const p = Skia.Path.Make();
              p.moveTo(0, 0); p.lineTo(-3, -18);
              p.moveTo(0, 0); p.lineTo(0, -22);
              p.moveTo(0, 0); p.lineTo(4, -16);
              p.moveTo(0, 0); p.lineTo(7, -12);
              return p;
            })()}
            strokeWidth={1.5}
            style="stroke"
            strokeCap="round"
            color={COLORS.pencil}
            opacity={0.5}
          />
        </Group>
      ))}
      {/* 小石块 */}
      <Group transform={[{ translate: [300, 600] }]}>
        <Path
          path={(() => {
            const p = Skia.Path.Make();
            p.moveTo(-12, 0);
            p.lineTo(-8, -10);
            p.lineTo(4, -12);
            p.lineTo(12, -5);
            p.lineTo(10, 2);
            p.close();
            return p;
          })()}
          color={COLORS.pencilLight}
          opacity={0.6}
        />
        <Path
          path={(() => {
            const p = Skia.Path.Make();
            p.moveTo(-8, -10); p.lineTo(-2, -6);
            p.moveTo(2, -10); p.lineTo(6, -4);
            return p;
          })()}
          strokeWidth={1}
          style="stroke"
          color={COLORS.pencil}
          opacity={0.4}
        />
      </Group>
    </Group>
  );
}

// 底部涟漪石台
function RipplePlatform({ elapsed }: { elapsed: number }) {
  const pulse = 1 + Math.sin(elapsed * 3) * 0.04; // 0.5Hz 呼吸
  return (
    <Group transform={[{ translate: [GAME.width / 2, GAME.wallLineY + 20] }]}>
      {/* 石台底座 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-90, 0);
          p.lineTo(-80, -15);
          p.lineTo(80, -15);
          p.lineTo(90, 0);
          p.lineTo(80, 12);
          p.lineTo(-80, 12);
          p.close();
          return p;
        })()}
        color={COLORS.pencilLight}
        opacity={0.5}
      />
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-80, -15); p.lineTo(80, -15);
          p.moveTo(-90, 0); p.lineTo(90, 0);
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        color={COLORS.pencil}
        opacity={0.6}
      />
      {/* 涟漪圈（3圈，呼吸缩放） */}
      {[0, 1, 2].map(i => {
        const r = (18 + i * 16) * pulse;
        return (
          <Circle
            key={i}
            cx={0}
            cy={-8}
            r={r}
            color="transparent"
            strokeWidth={1.5}
            style="stroke"
            // @ts-ignore
            strokeColor={COLORS.pencil}
            opacity={0.3 - i * 0.08}
          />
        );
      })}
    </Group>
  );
}

// 顶部灰雾刷怪区
function TopFog() {
  return (
    <Group>
      <Rect x={0} y={0} width={GAME.width} height={120} color={COLORS.pencilFaint} opacity={0.15} />
      {/* 雾的下缘不规则 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(0, 100);
          for (let x = 0; x <= GAME.width; x += 30) {
            const y = 100 + Math.sin(x * 0.05) * 15 + Math.sin(x * 0.12) * 8;
            p.lineTo(x, y);
          }
          p.lineTo(GAME.width, 0);
          p.lineTo(0, 0);
          p.close();
          return p;
        })()}
        color={COLORS.pencilFaint}
        opacity={0.12}
      />
    </Group>
  );
}

// ============ 主角：小白 ============

function XiaoBai({ player, elapsed }: { player: Player; elapsed: number }) {
  const p = player.pos;
  const breathe = 1 + Math.sin(elapsed * 2) * 0.015; // 待机动画：呼吸
  const staffSway = Math.sin(elapsed * 1.5) * 2; // 法杖微晃
  return (
    <Group transform={[{ translate: [p.x, p.y - 10] }, { scale: breathe }]}>
      {/* 法杖（在身体后面） */}
      <Group transform={[{ translate: [22, -10] }, { rotate: staffSway }]}>
        {/* 杖身 */}
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(0, 50);
            pp.lineTo(2, -40);
            return pp;
          })()}
          strokeWidth={4}
          style="stroke"
          strokeCap="round"
          color="#8B6914"
        />
        {/* 杖顶水晶 */}
        <Circle cx={2} cy={-46} r={7} color={COLORS.arcane} opacity={0.8} />
        <Circle cx={2} cy={-46} r={4} color={COLORS.arcaneLight} />
        {/* 水晶微光 */}
        <Circle cx={2} cy={-46} r={12} color={COLORS.arcane} opacity={0.15 + Math.sin(elapsed * 4) * 0.05} />
      </Group>

      {/* 身体（白袍） */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-22, 45);
          pp.lineTo(-26, 10);
          pp.quadTo(-28, -5, -20, -15);
          pp.lineTo(20, -15);
          pp.quadTo(28, -5, 26, 10);
          pp.lineTo(22, 45);
          pp.close();
          return pp;
        })()}
        color="#F5F2EC"
      />
      {/* 袍子轮廓线 */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-22, 45);
          pp.lineTo(-26, 10);
          pp.quadTo(-28, -5, -20, -15);
          pp.lineTo(20, -15);
          pp.quadTo(28, -5, 26, 10);
          pp.lineTo(22, 45);
          return pp;
        })()}
        strokeWidth={1.5}
        style="stroke"
        color={COLORS.pencil}
        opacity={0.7}
      />
      {/* 袍子褶皱 */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-10, 15); pp.lineTo(-12, 42);
          pp.moveTo(0, 10); pp.lineTo(0, 44);
          pp.moveTo(10, 15); pp.lineTo(12, 42);
          return pp;
        })()}
        strokeWidth={1}
        style="stroke"
        color={COLORS.pencilFaint}
      />

      {/* 兜帽 */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-22, -12);
          pp.quadTo(-24, -35, -8, -42);
          pp.quadTo(0, -48, 8, -42);
          pp.quadTo(24, -35, 22, -12);
          pp.quadTo(0, -20, -22, -12);
          pp.close();
          return pp;
        })()}
        color="#F0EDE6"
      />
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-22, -12);
          pp.quadTo(-24, -35, -8, -42);
          pp.quadTo(0, -48, 8, -42);
          pp.quadTo(24, -35, 22, -12);
          return pp;
        })()}
        strokeWidth={1.5}
        style="stroke"
        color={COLORS.pencil}
        opacity={0.7}
      />
      {/* 兜帽尖 */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-4, -42);
          pp.quadTo(-2, -52, 4, -50);
          pp.quadTo(2, -45, 4, -42);
          pp.close();
          return pp;
        })()}
        color="#E8E4DA"
      />

      {/* 脸部（兜帽阴影内） */}
      <Circle cx={0} cy={-22} r={13} color="#F5E6D3" />
      {/* 蒙眼布 */}
      <Rect x={-12} y={-26} width={24} height={6} color={COLORS.pencil} opacity={0.8} />
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-12, -23); pp.lineTo(-16, -20);
          pp.moveTo(12, -23); pp.lineTo(16, -20);
          return pp;
        })()}
        strokeWidth={1.5}
        style="stroke"
        color={COLORS.pencil}
        opacity={0.6}
      />
      {/* 红鼻子 */}
      <Circle cx={0} cy={-17} r={3} color={COLORS.red} opacity={0.8} />
      {/* 小嘴 */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-3, -12);
          pp.quadTo(0, -10, 3, -12);
          return pp;
        })()}
        strokeWidth={1.2}
        style="stroke"
        strokeCap="round"
        color={COLORS.pencil}
      />

      {/* 左手（自然下垂） */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-20, -5);
          pp.quadTo(-28, 10, -24, 28);
          return pp;
        })()}
        strokeWidth={5}
        style="stroke"
        strokeCap="round"
        color="#F0EDE6"
      />
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-20, -5);
          pp.quadTo(-28, 10, -24, 28);
          return pp;
        })()}
        strokeWidth={1}
        style="stroke"
        color={COLORS.pencil}
        opacity={0.4}
      />
      {/* 右手（持杖） */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(18, -5);
          pp.quadTo(24, 0, 22, 12);
          return pp;
        })()}
        strokeWidth={5}
        style="stroke"
        strokeCap="round"
        color="#F0EDE6"
      />

      {/* 脚 */}
      <Ellipse x={-10} y={46} rx={8} ry={4} color={COLORS.pencil} opacity={0.6} />
      <Ellipse x={10} y={46} rx={8} ry={4} color={COLORS.pencil} opacity={0.6} />
    </Group>
  );
}

// 辅助：椭圆（Skia 没有直接 Ellipse 组件，用 Circle scale 替代）
function Ellipse({ x, y, rx, ry, color, opacity }: any) {
  return (
    <Group transform={[{ translate: [x, y] }, { scaleX: rx / ry }, { scaleY: 1 }]}>
      <Circle cx={0} cy={0} r={ry} color={color} opacity={opacity} />
    </Group>
  );
}

// ============ 敌人绘制 ============

function ImpEnemy({ e }: { e: Enemy }) {
  // 小鬼面：简笔画鬼脸，幽灵形
  return (
    <Group transform={[{ translate: [e.pos.x, e.pos.y] }]}>
      {/* 幽灵身体 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius, e.radius * 0.3);
          p.quadTo(-e.radius, -e.radius, 0, -e.radius);
          p.quadTo(e.radius, -e.radius, e.radius, e.radius * 0.3);
          // 波浪底
          p.lineTo(e.radius * 0.6, e.radius * 0.6);
          p.lineTo(e.radius * 0.2, e.radius * 0.3);
          p.lineTo(-e.radius * 0.2, e.radius * 0.6);
          p.lineTo(-e.radius * 0.6, e.radius * 0.3);
          p.close();
          return p;
        })()}
        color="#F5F2EC"
      />
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius, e.radius * 0.3);
          p.quadTo(-e.radius, -e.radius, 0, -e.radius);
          p.quadTo(e.radius, -e.radius, e.radius, e.radius * 0.3);
          p.lineTo(e.radius * 0.6, e.radius * 0.6);
          p.lineTo(e.radius * 0.2, e.radius * 0.3);
          p.lineTo(-e.radius * 0.2, e.radius * 0.6);
          p.lineTo(-e.radius * 0.6, e.radius * 0.3);
          p.close();
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        color={COLORS.pencil}
      />
      {/* 大眼睛 */}
      <Circle cx={-e.radius * 0.35} cy={-e.radius * 0.2} r={e.radius * 0.22} color={COLORS.pencil} />
      <Circle cx={e.radius * 0.35} cy={-e.radius * 0.2} r={e.radius * 0.22} color={COLORS.pencil} />
      <Circle cx={-e.radius * 0.3} cy={-e.radius * 0.28} r={e.radius * 0.07} color="#fff" />
      <Circle cx={e.radius * 0.4} cy={-e.radius * 0.28} r={e.radius * 0.07} color="#fff" />
      {/* 微笑 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius * 0.25, e.radius * 0.15);
          p.quadTo(0, e.radius * 0.4, e.radius * 0.25, e.radius * 0.15);
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        strokeCap="round"
        color={COLORS.pencil}
      />
    </Group>
  );
}

function CloudEnemy({ e, elapsed }: { e: Enemy; elapsed: number }) {
  // 飘云怪：zZZZ 睡脸云朵
  const sleeping = e.state === 'sleeping';
  return (
    <Group transform={[{ translate: [e.pos.x, e.pos.y] }]}>
      {/* 云朵身体（多圆叠加） */}
      <Circle cx={-e.radius * 0.5} cy={e.radius * 0.1} r={e.radius * 0.55} color="#F5F2EC" />
      <Circle cx={e.radius * 0.4} cy={e.radius * 0.05} r={e.radius * 0.6} color="#F5F2EC" />
      <Circle cx={0} cy={-e.radius * 0.3} r={e.radius * 0.5} color="#F5F2EC" />
      <Circle cx={-e.radius * 0.15} cy={e.radius * 0.3} r={e.radius * 0.45} color="#F5F2EC" />
      {/* 云轮廓 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.addCircle(-e.radius * 0.5, e.radius * 0.1, e.radius * 0.55);
          p.addCircle(e.radius * 0.4, e.radius * 0.05, e.radius * 0.6);
          p.addCircle(0, -e.radius * 0.3, e.radius * 0.5);
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        color={COLORS.pencil}
      />
      {/* 睡脸：闭眼 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius * 0.35, -e.radius * 0.05);
          p.quadTo(-e.radius * 0.2, e.radius * 0.05, -e.radius * 0.05, -e.radius * 0.05);
          p.moveTo(e.radius * 0.05, -e.radius * 0.05);
          p.quadTo(e.radius * 0.2, e.radius * 0.05, e.radius * 0.35, -e.radius * 0.05);
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        strokeCap="round"
        color={COLORS.pencil}
      />
      {/* 小嘴（皱眉/不爽） */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius * 0.15, e.radius * 0.2);
          p.quadTo(0, e.radius * 0.1, e.radius * 0.15, e.radius * 0.2);
          return p;
        })()}
        strokeWidth={1.2}
        style="stroke"
        strokeCap="round"
        color={COLORS.pencil}
      />
      {/* zZZZ（用Path画Z形） */}
      {sleeping && (
        <Group transform={[{ translate: [e.radius * 0.7, -e.radius * 0.5] }]} opacity={0.5}>
          <Path path={(() => { const p = Skia.Path.Make(); p.moveTo(0, -4); p.lineTo(6, -4); p.lineTo(0, 2); p.lineTo(6, 2); return p; })()} strokeWidth={1.5} style="stroke" strokeCap="round" color={COLORS.pencilLight} />
          <Path path={(() => { const p = Skia.Path.Make(); p.moveTo(9, -10); p.lineTo(17, -10); p.lineTo(9, -2); p.lineTo(17, -2); return p; })()} strokeWidth={2} style="stroke" strokeCap="round" color={COLORS.pencil} />
          <Path path={(() => { const p = Skia.Path.Make(); p.moveTo(20, -18); p.lineTo(30, -18); p.lineTo(20, -8); p.lineTo(30, -8); return p; })()} strokeWidth={2.5} style="stroke" strokeCap="round" color={COLORS.pencil} />
        </Group>
      )}
    </Group>
  );
}

function TwinEnemy({ e }: { e: Enemy }) {
  // 双子面：双脸叠放
  const raging = e.state === 'raging';
  return (
    <Group transform={[{ translate: [e.pos.x, e.pos.y] }]}>
      {/* 上面的脸（ smug 得意） */}
      <Circle cx={0} cy={-e.radius * 0.6} r={e.radius * 0.75} color="#F5F2EC" />
      <Circle cx={0} cy={-e.radius * 0.6} r={e.radius * 0.75} strokeWidth={1.5} style="stroke" color={COLORS.pencil} />
      {/* 眯眼（得意） */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius * 0.4, -e.radius * 0.65);
          p.quadTo(-e.radius * 0.25, -e.radius * 0.55, -e.radius * 0.1, -e.radius * 0.65);
          p.moveTo(e.radius * 0.1, -e.radius * 0.65);
          p.quadTo(e.radius * 0.25, -e.radius * 0.55, e.radius * 0.4, -e.radius * 0.65);
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        strokeCap="round"
        color={COLORS.pencil}
      />
      {/* 坏笑 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius * 0.3, -e.radius * 0.4);
          p.quadTo(0, -e.radius * 0.25, e.radius * 0.3, -e.radius * 0.4);
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        strokeCap="round"
        color={COLORS.pencil}
      />

      {/* 下面的脸（开心） */}
      <Circle cx={0} cy={e.radius * 0.5} r={e.radius * 0.7} color="#F5F2EC" />
      <Circle cx={0} cy={e.radius * 0.5} r={e.radius * 0.7} strokeWidth={1.5} style="stroke" color={COLORS.pencil} />
      {/* 圆眼 */}
      <Circle cx={-e.radius * 0.25} cy={e.radius * 0.4} r={e.radius * 0.12} color={COLORS.pencil} />
      <Circle cx={e.radius * 0.25} cy={e.radius * 0.4} r={e.radius * 0.12} color={COLORS.pencil} />
      {/* 张嘴笑 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius * 0.25, e.radius * 0.6);
          p.quadTo(0, e.radius * 0.85, e.radius * 0.25, e.radius * 0.6);
          return p;
        })()}
        strokeWidth={1.5}
        style="stroke"
        strokeCap="round"
        color={COLORS.pencil}
      />

      {/* 狂暴标记（用Path画!） */}
      {raging && (
        <Group transform={[{ translate: [e.radius * 0.8, -e.radius * 0.8] }]}>
          <Path path={(() => { const p = Skia.Path.Make(); p.moveTo(0, -10); p.lineTo(0, 2); return p; })()} strokeWidth={3} style="stroke" strokeCap="round" color={COLORS.red} />
          <Circle cx={0} cy={7} r={2} color={COLORS.red} />
        </Group>
      )}
    </Group>
  );
}

function InkEliteEnemy({ e }: { e: Enemy }) {
  // 墨团精英：黑色墨滴，怒眼
  return (
    <Group transform={[{ translate: [e.pos.x, e.pos.y] }]}>
      {/* 墨滴身体 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(0, -e.radius);
          p.quadTo(e.radius * 0.8, -e.radius * 0.3, e.radius * 0.7, e.radius * 0.3);
          p.quadTo(e.radius * 0.5, e.radius, 0, e.radius);
          p.quadTo(-e.radius * 0.5, e.radius, -e.radius * 0.7, e.radius * 0.3);
          p.quadTo(-e.radius * 0.8, -e.radius * 0.3, 0, -e.radius);
          p.close();
          return p;
        })()}
        color={COLORS.inkBlack}
      />
      {/* 墨滴光泽 */}
      <Circle cx={-e.radius * 0.3} cy={-e.radius * 0.2} r={e.radius * 0.15} color="#333" opacity={0.5} />
      {/* 怒眼（斜眉） */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          // 左眉
          p.moveTo(-e.radius * 0.5, -e.radius * 0.15);
          p.lineTo(-e.radius * 0.15, -e.radius * 0.05);
          // 右眉
          p.moveTo(e.radius * 0.5, -e.radius * 0.15);
          p.lineTo(e.radius * 0.15, -e.radius * 0.05);
          return p;
        })()}
        strokeWidth={3}
        style="stroke"
        strokeCap="round"
        color={COLORS.red}
      />
      {/* 眼睛 */}
      <Circle cx={-e.radius * 0.3} cy={e.radius * 0.05} r={e.radius * 0.12} color="#fff" />
      <Circle cx={e.radius * 0.3} cy={e.radius * 0.05} r={e.radius * 0.12} color="#fff" />
      <Circle cx={-e.radius * 0.28} cy={e.radius * 0.07} r={e.radius * 0.06} color={COLORS.inkBlack} />
      <Circle cx={e.radius * 0.32} cy={e.radius * 0.07} r={e.radius * 0.06} color={COLORS.inkBlack} />
      {/* 怒嘴 */}
      <Path
        path={(() => {
          const p = Skia.Path.Make();
          p.moveTo(-e.radius * 0.25, e.radius * 0.4);
          p.quadTo(0, e.radius * 0.25, e.radius * 0.25, e.radius * 0.4);
          return p;
        })()}
        strokeWidth={2}
        style="stroke"
        strokeCap="round"
        color={COLORS.red}
      />
    </Group>
  );
}

function EnemySprite({ e, elapsed }: { e: Enemy; elapsed: number }) {
  switch (e.type) {
    case 'imp': return <ImpEnemy e={e} />;
    case 'cloud': return <CloudEnemy e={e} elapsed={elapsed} />;
    case 'twin': return <TwinEnemy e={e} />;
    case 'ink_elite': return <InkEliteEnemy e={e} />;
  }
}

// ============ 弹道 ============

function ProjectileSprite({ p }: { p: Projectile }) {
  const angle = Math.atan2(p.vel.y, p.vel.x) + Math.PI / 2;
  const fade = Math.max(0.3, 1 - p.life / p.maxLife);

  if (p.kind === 'arcane') {
    // 奥术飞弹：紫色菱形光球
    return (
      <Group transform={[{ translate: [p.pos.x, p.pos.y] }, { rotate: angle }]}>
        <Circle cx={0} cy={0} r={10} color={COLORS.arcane} opacity={fade * 0.3} />
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(0, -8);
            pp.lineTo(5, 0);
            pp.lineTo(0, 8);
            pp.lineTo(-5, 0);
            pp.close();
            return pp;
          })()}
          color={COLORS.arcane}
          opacity={fade}
        />
        <Circle cx={0} cy={0} r={2.5} color={COLORS.arcaneLight} opacity={fade} />
      </Group>
    );
  }

  if (p.kind === 'ice') {
    // 冰锥：蓝色尖锥
    return (
      <Group transform={[{ translate: [p.pos.x, p.pos.y] }, { rotate: angle }]}>
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(0, -12);
            pp.lineTo(5, 6);
            pp.lineTo(0, 3);
            pp.lineTo(-5, 6);
            pp.close();
            return pp;
          })()}
          color={COLORS.blue}
          opacity={fade}
        />
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(0, -10);
            pp.lineTo(2, 2);
            return pp;
          })()}
          strokeWidth={1}
          style="stroke"
          color="#fff"
          opacity={fade * 0.6}
        />
      </Group>
    );
  }

  // 滚木：棕色横木（宽横扫）
  return (
    <Group transform={[{ translate: [p.pos.x, p.pos.y] }]}>
      <Rect x={-40} y={-8} width={80} height={16} color="#8B6914" opacity={fade} />
      <Rect x={-40} y={-8} width={80} height={16} strokeWidth={1.5} style="stroke" color={COLORS.pencil} opacity={fade * 0.5} />
      {/* 木纹 */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-30, -3); pp.lineTo(-20, -3);
          pp.moveTo(10, 2); pp.lineTo(30, 2);
          pp.moveTo(-5, 4); pp.lineTo(5, 4);
          return pp;
        })()}
        strokeWidth={1}
        style="stroke"
        color="#6B4914"
        opacity={fade * 0.5}
      />
    </Group>
  );
}

// ============ 主画布 ============

export function GameCanvas({ player, enemies, projectiles, elapsed }: Props) {
  return (
    <Canvas style={styles.canvas}>
      {/* 纸张底色 */}
      <Rect x={0} y={0} width={GAME.width} height={GAME.height} color={COLORS.paper} />

      {/* 纸张纹理（淡墨点） */}
      <Group opacity={0.04}>
        {Array.from({ length: 30 }).map((_, i) => (
          <Circle
            key={i}
            cx={(i * 47) % GAME.width}
            cy={(i * 83) % GAME.height}
            r={1 + (i % 3)}
            color={COLORS.pencil}
          />
        ))}
      </Group>

      {/* 远景铅笔山 */}
      <PencilMountains />

      {/* 中景草丛石头 */}
      <GrassAndRocks />

      {/* 顶部灰雾刷怪区 */}
      <TopFog />

      {/* 敌人 */}
      {enemies.map(e => (
        <Group key={e.id}>
          <EnemySprite e={e} elapsed={elapsed} />
          {/* 血条（非满血且非精英） */}
          {e.hp < e.maxHp && e.type !== 'ink_elite' && (
            <Rect
              x={e.pos.x - e.radius}
              y={e.pos.y - e.radius - 8}
              width={e.radius * 2}
              height={3}
              color={COLORS.pencilFaint}
              opacity={0.5}
            />
          )}
          {e.hp < e.maxHp && e.type !== 'ink_elite' && (
            <Rect
              x={e.pos.x - e.radius}
              y={e.pos.y - e.radius - 8}
              width={e.radius * 2 * Math.max(0, e.hp / e.maxHp)}
              height={3}
              color={COLORS.green}
            />
          )}
          {/* 精英血条（更宽） */}
          {e.type === 'ink_elite' && (
            <>
              <Rect
                x={e.pos.x - e.radius}
                y={e.pos.y - e.radius - 12}
                width={e.radius * 2}
                height={5}
                color={COLORS.pencilFaint}
                opacity={0.5}
              />
              <Rect
                x={e.pos.x - e.radius}
                y={e.pos.y - e.radius - 12}
                width={e.radius * 2 * Math.max(0, e.hp / e.maxHp)}
                height={5}
                color={COLORS.red}
              />
            </>
          )}
        </Group>
      ))}

      {/* 弹道 */}
      {projectiles.map(p => (
        <ProjectileSprite key={p.id} p={p} />
      ))}

      {/* 底部涟漪石台 */}
      <RipplePlatform elapsed={elapsed} />

      {/* 主角小白 */}
      <XiaoBai player={player} elapsed={elapsed} />
    </Canvas>
  );
}

const styles = StyleSheet.create({
  canvas: {
    width: GAME.width,
    height: GAME.height,
  },
});
