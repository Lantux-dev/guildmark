# Guildmark

**Una hermandad viva para WoW Forever.** Eventos con calendario, buscador de grupo,
una economía propia de insignias (subastas, cofre, tienda, pedidos del banco), caza de
hermandades enemigas, auxilio y asaltos a capitales con toda tu facción, tribus, un
perfil con medallas y logros de hermandad con su propio nivel.

*English below.*

---

## Qué hace

**Hermandad**
- **Ahora:** quién está conectado, qué hace (mazmorra, banda, campo de batalla, mundo) y con quién va.
- **Miembros:** la ficha de cada uno con profesiones, mazmorras completadas, rango JcJ, campos de batalla y capa.
- **Tribus:** grupos de jugadores que juegan juntos, con su icono, su líder y su clasificación.
- **Clasificación:** reputación, cazadores, recolectores, encargos, mazmorras y JcJ.
- **Crónica:** mazmorras, bandas y eventos de la hermandad.
- **Cofre:** las insignias de toda la hermandad. Se invierten en **proyectos** (el estandarte de la hermandad en el retrato de todos, o eventos con más insignias: mazmorras, campos de batalla, caza, artesanía…) y pagan los **pedidos del banco**.
- **Banco de la hermandad:** las aportaciones de oro y objetos se registran solas al abrir el banco. Un oficial pide lo que hace falta («200 menas de cobre») y quien lo deposita cobra insignias del cofre.

**Eventos** con calendario mensual, inscripción por rol (tanque, sanador, DPS),
recordatorios y asistencia confirmada sola si vas en grupo con la hermandad.

**JcE**
- **Buscador de grupo interno:** creas un grupo, la hermandad pide plaza y tú invitas con un clic.
- **Tiempos de mazmorra** de la hermandad.
- **Mazmorras completadas** leídas de las estadísticas del juego, con desafíos por mazmorra.

**JcJ**
- **Objetivos de caza:** las hermandades enemigas que os persiguen, con su jugador más peligroso.
- **Cabezas con precio:** pon insignias por la cabeza de un enemigo. Con el **botín de guerra** ganas más cazando, pero si te matan pierdes parte de tus insignias y tu asesino pasa a tener precio: si la hermandad lo caza, recuperas la mitad.
- **Auxilio:** si una hermandad enemiga os caza, pide ayuda a toda tu facción. Quien acude entra en vuestra banda, en vuestra capa.
- **Asaltos** a las capitales enemigas: el líder derribado queda registrado, con el tiempo que tardasteis.
- **Campos de batalla:** victorias y derrotas de cada uno, con su recompensa. Lo que pasa dentro no cuenta como caza ni pide auxilio.

**Facción:** clasificación de las hermandades de tu facción esta temporada, directorio
de hermandades con el addon, récords y Horda contra Alianza.

**Mercado**
- **Subasta con insignias** (nunca oro): cualquiera subasta lo suyo durante un día y cobra el 90 %; el 10 % va al cofre. Los oficiales subastan objetos del banco.
- **Gremios:** el recetario de toda la hermandad por profesión y categoría.
- **Encargos:** a un artesano o al gremio entero; el primero que acepta se lo queda. La entrega se detecta sola en el intercambio.
- **Tienda:** marcos y terciopelos para tu perfil, y las tasas para fundar una tribu o cambiar su icono.

**Perfil:** un estuche de medallas (bronce, plata y oro) por lo que haces por tu hermandad,
tu ficha de rol (título, papel, lema e historia) y las insignias que llevas junto al retrato:
el estandarte de tu hermandad, tu tribu, tu rango JcJ, tus medallas y los honores de la
hermandad. Los demás jugadores con el addon también los ven.

**Logros de hermandad**, con nivel de hermandad (1 a 10) y recompensas: títulos, avisos
dorados, insignias especiales, marco dorado…

## Las insignias

Se **ganan** con eventos, mazmorras, caza, campos de batalla, encargos, auxilio, pedidos
del banco y cabezas cobradas. Se **gastan** en la subasta, la tienda, el cofre y las
recompensas por cabezas. Cada miércoles bajan un 5 %, y eso va al cofre. La **reputación**
no se gasta: sube tu rango en la hermandad.

## Rangos y permisos

El addon usa los rangos de tu hermandad. El maestro de la hermandad decide en Ajustes qué
rango puede crear eventos, subastar objetos del banco, abrir proyectos, hacer pedidos y
ajustar puntos, y puede renombrar los rangos del addon (Recluta, Miembro, Veterano, Élite).

Las novedades (subastas, pedidos, proyectos, eventos, tribus, cabezas con precio) se
anuncian en el **chat de hermandad**, para que las vean también quienes no tienen el addon.

## Cómo funciona

Todo va **entre los addons de los jugadores**, sin servidores externos:
- **Dentro de la hermandad:** por su canal de addons.
- **Entre hermandades de la misma facción:** por un canal oculto.
- **Con la otra facción:** a través de amigos de Battle.net que tengan el addon.

Los puntos, las insignias y los logros los **calcula cada addon** con las mismas reglas a
partir de los datos sincronizados, así que nadie puede inventarse un saldo. Además, el addon
avisa a los oficiales de datos sospechosos.

## Privacidad

Antes de compartir nada, el addon te enseña qué se comparte y te pide permiso. Del banco
de la hermandad solo se apuntan los movimientos de quien ha aceptado.
- **Cambiar o retirar el permiso:** `/gmk privacidad`.
- **Borrar tus datos** aquí y en los addons de tu hermandad: `/gmk borrar`.
- **Nunca se recoge** el contenido del chat.

## Comandos

| Comando | Qué hace |
|---|---|
| `/gmk` o `/guildmark` | Abrir o cerrar la ventana |
| `/gmk perfil [nombre]` | Tu perfil o el de otro miembro |
| `/gmk logros` | Logros de hermandad |
| `/gmk subasta [objeto]` | Subastar un objeto tuyo |
| `/gmk ajustes` | Opciones, rangos y permisos |
| `/gmk privacidad` | Qué se comparte y el permiso |
| `/gmk borrar` | Borrar tus datos |
| `/gmk prueba` | Modo prueba: tu grupo hace de hermandad, para probarlo sin tocar tu hermandad real |

Todos los comandos tienen su equivalente en inglés (`profile`, `privacy`, `settings`, `test`…).

## Instalar

Desde **CurseForge** (recomendado) o a mano: descomprime la carpeta `Guildmark` en
`World of Warcraft\<versión>\Interface\AddOns\`.

## Licencia

Código bajo **GPL-3.0** (ver [`LICENSE`](LICENSE)). El nombre, el logo y el arte propio
de Guildmark están reservados (ver [`NOTICE.md`](NOTICE.md)). Para desarrollar:
[`docs/desarrollo.md`](docs/desarrollo.md).

---

# Guildmark (English)

**A living guild for WoW Forever.** Events with a calendar, a group finder, its own badge
economy (auctions, chest, shop, bank requests), hunting enemy guilds, calls for help and
capital assaults with your whole faction, tribes, a profile with medals and guild
achievements with their own level.

## Features

**Guild**
- **Now:** who is online, what they are doing (dungeon, raid, battleground, world) and who they are grouped with.
- **Members:** each member's card with professions, completed dungeons, PvP rank, battlegrounds and layer.
- **Tribes:** groups of players who play together, with their icon, their leader and their ranking.
- **Ranking:** reputation, hunters, gatherers, orders, dungeons and PvP.
- **Chronicle:** guild dungeons, raids and events.
- **Chest:** the whole guild's badges. They fund **projects** (the guild standard on every portrait, or boosted events: dungeons, battlegrounds, hunting, crafting…) and pay for **bank requests**.
- **Guild bank:** gold and item deposits are recorded automatically when the bank is opened. An officer asks for what is needed ("200 copper ore") and whoever deposits it gets badges from the chest.

**Events** with a monthly calendar, sign-up by role (tank, healer, DPS), reminders, and
attendance confirmed automatically when you are grouped with the guild.

**PvE**
- **Internal group finder:** create a group, guildmates ask to join and you invite them in one click.
- **Guild dungeon times.**
- **Completed dungeons** read from the game's statistics, with per-dungeon challenges.

**PvP**
- **Hunting targets:** the enemy guilds that hunt you, with their most dangerous player.
- **Bounties:** put badges on an enemy's head. With **war spoils** on you earn more when hunting, but if you die you lose some badges and your killer gets a bounty: if the guild hunts them down, you get half back.
- **Calls for help:** if an enemy guild hunts you, ask your whole faction for help. Those who answer join your raid, on your layer.
- **Assaults** on enemy capitals: a fallen leader is recorded, together with how long it took.
- **Battlegrounds:** everyone's wins and losses, with their reward. What happens inside doesn't count as hunting or trigger calls for help.

**Faction:** ranking of your faction's guilds this season, a directory of guilds with the
addon, records and Horde vs Alliance.

**Market**
- **Badge auction** (never gold): anyone can auction their own items for a day and gets 90%; 10% goes to the chest. Officers auction guild bank items.
- **Crafters:** the whole guild's recipe book by profession and category.
- **Orders:** to one crafter or to all of them; the first to accept takes it. Delivery is detected automatically in the trade window.
- **Shop:** frames and velvets for your profile, plus the fees to found a tribe or change its icon.

**Profile:** a medal case (bronze, silver and gold) for what you do for your guild, your
character sheet (title, role, motto and story) and the badges you wear next to your
portrait: your guild's standard, your tribe, your PvP rank, your medals and your guild's
honors. Other players with the addon see them too.

**Guild achievements**, with a guild level (1 to 10) and rewards: titles, golden alerts,
special badges, a golden frame…

## Badges

You **earn** them with events, dungeons, hunting, battlegrounds, orders, calls for help,
bank requests and claimed bounties. You **spend** them in the auction, the shop, the chest
and on bounties. Every Wednesday they drop 5%, and that goes to the chest. **Reputation** is
never spent: it raises your guild rank.

## Ranks and permissions

The addon uses your guild's ranks. In Settings, the guild master decides which rank can
create events, auction bank items, open projects, make bank requests and adjust points, and
can rename the addon ranks (Recruit, Member, Veteran, Elite).

News (auctions, requests, projects, events, tribes, bounties) is announced in **guild chat**,
so members without the addon see it too.

## How it works

Everything travels **between the players' addons**, with no external servers:
- **Within the guild:** through its addon channel.
- **Between guilds of the same faction:** through a hidden channel.
- **With the other faction:** through Battle.net friends who have the addon.

Points, badges and achievements are **calculated by every addon** with the same rules from
the synced data, so nobody can make up a balance. The addon also warns officers about
suspicious data.

## Privacy

Before sharing anything, the addon shows you what is shared and asks for your consent.
Guild bank activity is only recorded for those who have accepted.
- **Change or withdraw consent:** `/gmk privacy`.
- **Delete your data** here and in your guild's addons: `/gmk delete`.
- Chat content is **never** collected.

## Commands

| Command | What it does |
|---|---|
| `/gmk` or `/guildmark` | Open or close the window |
| `/gmk profile [name]` | Your profile or another member's |
| `/gmk achievements` | Guild achievements |
| `/gmk auction [item]` | Auction one of your items |
| `/gmk settings` | Options, ranks and permissions |
| `/gmk privacy` | What is shared and your consent |
| `/gmk delete` | Delete your data |
| `/gmk test` | Test mode: your group acts as the guild, to try it without touching your real guild |

## Install

From **CurseForge** (recommended) or manually: unzip the `Guildmark` folder into
`World of Warcraft\<version>\Interface\AddOns\`.

## License

Code under **GPL-3.0** (see [`LICENSE`](LICENSE)). The Guildmark name, logo and own art are
reserved (see [`NOTICE.md`](NOTICE.md)).
