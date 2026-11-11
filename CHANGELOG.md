# Cambios · Changelog

## 1.2.0 · 2026-11

- **PvP kills stay in sync between online members:** if the live message about a kill got lost (the game drops messages when there is a lot of traffic), members who were online never got it until they logged in again. Now each player regularly sends a tiny summary of how many of their own kills and deaths they have from today and yesterday, and anyone missing some asks them for the rest.
- **New: PvP > Hunters.** Its own tab for the guild hunters: kill streaks happening right now, a podium (last 7 or 30 days) with kills, deaths, K/D, revenges, honor and favourite victim, the rest of the ranking, and streak records.
- **Kill streaks:** honorable kills in a row without dying to another player (battlegrounds don't count). Three new guild achievements: Unstoppable (5), No Mercy (10) and Legend of the Frontier (20).
- **Participation ranking (PvP > Hunters):** switch between killing blows and participation. Participation uses the game's world honorable kills statistic (no battlegrounds), which counts everyone who helps with a kill, so healers and tanks rank fairly. All-time totals straight away, plus the last 7 or 30 days (counted from when you install 1.2.0).
- **New: Faction > Hunters.** The same for your whole faction: streaks happening right now, the top 15 by killing blows or participation (7 days, 30 days or all time) and the streak records, with each player's guild. Every guild shares its top 5 of each list on the guild network.
- **New: PvP > Log.** The latest kills and deaths now have their own section (up to 60), with a filter for all, kills or deaths. Targets is lighter.
- **Fixed: missing icons.** The Decorated, Hall of Heroes and Chest of Medals achievements, the Feats of Strength category, war league trophies and the guild level-up banner used trophy icons that don't exist in Forever; they now have their own.

---

- **Las muertes de JcJ se mantienen iguales entre los conectados:** si se perdía el aviso en directo de una muerte (el juego descarta mensajes cuando hay mucho tráfico), los que estaban conectados no la recibían hasta volver a entrar. Ahora cada jugador manda de vez en cuando un resumen pequeñito de cuántas bajas y muertes suyas tiene de hoy y de ayer, y a quien le falte alguna se la pide.
- **Nuevo: JcJ > Cazadores.** Pestaña propia para los cazadores de la hermandad: rachas en curso, podio (últimos 7 o 30 días) con bajas, muertes, K/D, venganzas, honor y víctima favorita, el resto de la clasificación y los récords de racha.
- **Rachas de bajas:** bajas con honor seguidas sin caer ante otro jugador (los campos de batalla no cuentan). Tres logros de hermandad nuevos: Imparable (5), Sin piedad (10) y Leyenda de la frontera (20).
- **Clasificación por participación (JcJ > Cazadores):** botón para cambiar entre golpes de gracia y participación. La participación usa la estadística del juego de muertes con honor en el mundo (sin campos de batalla), que cuenta a todos los que ayudan en la baja: sanadores y tanques salen como merecen. El total de siempre desde el primer momento, y los últimos 7 o 30 días (contando desde que instalas la 1.2.0).
- **Nuevo: Facción > Cazadores.** Lo mismo para toda tu facción: rachas en curso, los 15 mejores por golpes de gracia o participación (7 días, 30 días o total) y los récords de racha, con la hermandad de cada uno. Cada hermandad comparte sus 5 mejores de cada lista en la red de hermandades.
- **Nuevo: JcJ > Registro.** Las últimas kills y muertes tienen su propio apartado (hasta 60), con filtro de todo, cazas o caídos. Objetivos queda más ligero.
- **Arreglado: iconos que no se veían.** Los logros Condecorados, Galería de héroes y Pecho de medallas, la categoría Proezas de fuerza, los trofeos de liga de las guerras y el cartel de subida de nivel usaban iconos de trofeo que no existen en Forever; ahora tienen los suyos.

## 1.1.5 · 2026-11

- **Fixed: guild achievement banner only showed for one member.** It appeared only on the addon that noticed the achievement first; everyone else just received it silently. Now every online member sees the banner (only for achievements earned in the last 10 minutes).
- **New settings (Settings > Warnings):** turn off guild achievement banners on screen (personal), and stop the addon posting guild achievements in guild chat (guild setting, changed by officers).
- **Faction records only count guild groups:** the season's best dungeon times now only count runs done with a guild group (4 or 5 from the guild), the same rule as completed dungeons. Before, a time with a group of strangers could show up as the guild's record.

---

- **Arreglado: el cartel de logro de hermandad solo le salía a uno.** Aparecía únicamente en el addon que se daba cuenta primero; a los demás les llegaba sin aviso. Ahora lo ven todos los conectados (solo para logros conseguidos en los últimos 10 minutos).
- **Ajustes nuevos (Ajustes > Avisos):** quitar los carteles de logro de hermandad en pantalla (personal) y que el addon no escriba los logros de hermandad en el chat de hermandad (ajuste de hermandad, lo cambian los oficiales).
- **Los récords de facción solo cuentan grupos de hermandad:** los mejores tiempos de mazmorra de la temporada solo cuentan las partidas hechas con grupo de hermandad (4 o 5 de la guild), la misma regla que las mazmorras completadas. Antes, un tiempo con un grupo de desconocidos podía salir como récord de la hermandad.

## 1.1.4 · 2026-11

- **Fewer stutters:** every guild message (activity, guilds seen, member records...) recalculated the whole guild's points on the spot, even when it didn't affect them. Points are now only recalculated when something that counts for them changes, and refreshes are grouped (at most once per second, once every 3 seconds in combat). Working out kills on target guilds also went through the whole history for every kill; it now does a single pass and is far faster.
- **New: `/gmk performance`** shows which parts of the addon take the most time and how many stutters they caused, so slowdowns can be reported.

---

- **Menos tirones:** cada mensaje de la hermandad (actividad, hermandades vistas, fichas...) recalculaba al momento los puntos de toda la hermandad, aunque no les afectara. Ahora los puntos solo se recalculan cuando cambia algo que cuenta para ellos, y los refrescos se agrupan (como mucho uno por segundo, uno cada 3 segundos en combate). Además, el cálculo de las bajas a hermandades objetivo repasaba todo el historial por cada baja; ahora lo recorre una sola vez y tarda muchísimo menos.
- **Nuevo: `/gmk rendimiento`** muestra qué partes del addon gastan más tiempo y cuántos tirones han causado, para poder avisar si algo va lento.

## 1.1.3 · 2026-11

- **Arreglado: error «script ran too long» al sincronizar.** En hermandades grandes, contestar a quien acababa de entrar obligaba a comprimir todo el estado de la hermandad de golpe, se pasaba del tiempo que deja el juego y quien entraba se quedaba sin sincronizar. Ahora sale en varios mensajes más pequeños.
- **Arreglado: logros repetidos en el chat.** Quien entraba sin tener aún toda la sincronización podía anunciar como nuevo un logro que la hermandad ya tenía. Ahora se espera a recibirla entera y, si aun así alguien lo da por nuevo, los que ya lo tenían le avisan antes de que salga en el chat.
- **Arreglado: la colecta del banco no le llegaba a quien instalaba el addon.** Ahora el tesorero (o el maestro de hermandad, si el tesorero no está) le pasa la colecta y las aportaciones a quien entra sin tenerlas.

---

- **Fixed: "script ran too long" error when syncing.** In big guilds, answering a guildmate who just logged in meant compressing the whole guild state at once, which ran past the game's time limit and left them unsynced. It now goes out in several smaller messages.
- **Fixed: repeated achievements in chat.** Someone logging in before receiving the full sync could announce an achievement the guild already had as new. The addon now waits for the whole sync and, if someone still reports it as new, those who already had it tell them before it reaches the chat.
- **Fixed: the bank fundraiser didn't reach people who just installed the addon.** The treasurer (or the guild master, if the treasurer is offline) now sends the fundraiser and its donations to anyone who logs in without them.

## 1.1.2 · 2026-11

- **Arreglado: cada uno veía bajas distintas** (por ejemplo en «Cazadores de la semana»). Si te perdías unas bajas de un compañero y luego veías en directo otra suya más reciente, las anteriores ya no te llegaban nunca. Ahora, al entrar, el addon compara cuántas bajas y mazmorras tiene de cada compañero y día de las últimas tres semanas y pide los días que no cuadran. Además, quien entra le devuelve a quien le contesta lo que a este le faltaba, así que cada entrada arregla a los dos. Lo que ya falta se va recuperando solo a medida que entráis con la 1.1.2.
- **Colecta para abrir el banco:** el maestro de hermandad crea una colecta de oro (por defecto 100 de oro) y elige tesorero. Se dona dándole el oro al tesorero por intercambio (sin poner nada a cambio) o por correo: su addon lo apunta solo, así que la barra es la misma para todos y nadie se apunta oro de más. Cada moneda de oro da 2 de reputación y 2 insignias, quien dona queda como **fundador del banco** (sale en su ficha y en la placa de fundadores del banco) y la hermandad gana el logro **«Las arcas de la hermandad»** al llegar a la meta. Lo que sobra va al banco.
- **Lista de miembros:** ordénala por nombre, nivel, rango, insignias o zona (clic otra vez para invertir el orden) y oculta o muestra los desconectados. Se recuerda lo que elijas.
- **Barra de reputación más clara:** si ya tienes la reputación del rango siguiente y solo te falta antigüedad, la barra sale llena con un ✔ en lugar de «130 / 100». La reputación no tiene tope semanal; los topes de 100 son de insignias.

---

- **Fixed: everyone saw different kill counts** (e.g. in "Hunters of the week"). If you missed some of a guildmate's kills and then saw a newer one live, the earlier ones never reached you. On login the addon now compares how many kills and dungeons it has from each guildmate per day over the last three weeks and asks for the days that don't match. Whoever logs in also sends back what the responder was missing, so each login fixes both sides. Records already missing are recovered as people log in with 1.1.2.
- **Fundraiser to open the bank:** the guild master starts a gold fundraiser (100 gold by default) and picks a treasurer. Members donate by giving the treasurer gold by trade (asking nothing in return) or by mail: the treasurer's addon records it automatically, so everyone sees the same bar and nobody can add fake gold. Each gold coin gives 2 reputation and 2 badges, donors become **bank founders** (shown on their member card and on the bank's founders plaque) and the guild earns the **"The Guild Coffers"** achievement when the goal is reached. Any surplus goes into the bank.
- **Member list:** sort by name, level, rank, badges or zone (click again to reverse) and show or hide offline members. Your choice is remembered.
- **Clearer reputation bar:** if you already have the reputation for the next rank and only need more time in the guild, the bar shows full with a ✔ instead of "130 / 100". Reputation has no weekly cap; the 100 caps are for badges.

## 1.1.1 · 2026-11

- **Arreglado: las bajas y mazmorras de los demás no llegaban.** Al entrar, el addon pedía solo lo posterior a su último registro, así que una baja tuya reciente tapaba las de los demás de antes. Ahora pide lo que le falta de cada miembro. Funciona del todo cuando quien te contesta también tiene la 1.1.1: actualizad todos.
- **Bajas con honor:** cualquier baja que te dé honor vale 5 insignias. Las de jugadores grises siguen sin dar nada.
- **Las venganzas pagan siempre:** matar a quien acaba de matar a un compañero da 10 insignias + 5 de venganza, aunque no tenga hermandad o su hermandad no sea objetivo.
- **Tribus más baratas:** fundar una cuesta 50 insignias repartidas entre los fundadores; cada uno paga su parte al aceptar. Quien pagó 100 recupera la diferencia.
- **Avisos nuevos en el chat de hermandad:** logros de hermandad, subidas de nivel de hermandad y rangos de profesión (Oficial, Experto, Artesano…).
- **Escape cierra la ventana** de Guildmark (en combate no: ahí, la X).
- **Cartel nuevo para los logros de hermandad:** grande, arriba de la pantalla y con brillo si la hermandad tiene el aviso dorado. También sale uno cuando la hermandad sube de nivel. `/gmk aviso` enseña una muestra.
- **Arreglado: logros de hermandad repetidos en el chat** cuando alguien instala el addon o entra: ahora espera a la sincronización antes de anunciar y no anuncia lo que la hermandad ya tenía.

---

- **Fixed: other members' kills and dungeons weren't arriving.** On login the addon only asked for records newer than its latest one, so a recent kill of yours hid everyone else's earlier ones. It now asks for what it's missing from each member. It fully works once whoever answers you also has 1.1.1: everyone should update.
- **Honorable kills:** any kill that gives you honor is worth 5 badges. Grey players still give nothing.
- **Revenge always pays:** killing whoever just killed a guildmate gives 10 badges + 5 for revenge, even if they have no guild or their guild isn't a target.
- **Cheaper tribes:** founding one costs 50 badges split between the founders; each pays their share when accepting. Anyone who paid 100 gets the difference back.
- **New guild chat announcements:** guild achievements, guild level-ups and profession ranks (Journeyman, Expert, Artisan…).
- **Escape closes the Guildmark window** (not in combat: use the X there).
- **New banner for guild achievements:** large, at the top of the screen, with a shine if the guild has the golden alert. One also appears when the guild levels up. `/gmk toast` shows a sample.
- **Fixed: guild achievements announced again in chat** when someone installs the addon or logs in: it now waits for the sync before announcing, and skips anything the guild already had.

## 1.1.0 · 2026-11

- **Nuevo: sección Banco.** Lo que hay de verdad en el banco de la hermandad, como se ve en el juego (pestañas, huecos, cantidades y oro). Se actualiza cada vez que alguien con el addon abre el banco. El maestro decide en Ajustes qué rangos ven cada pestaña.
- **Peticiones al banco:** clic en un objeto para pedirlo. Llega a quien tenga el permiso nuevo «Entregar objetos del banco»; la retirada se comprueba con el registro del banco y la entrega con el intercambio (o se marca a mano).
- Los pedidos de depósito y el registro de aportaciones pasan del cofre a la sección Banco.
- **Encargos:** casilla «Pongo yo los materiales» con la lista de lo que pide la receta, y propina en oro, plata y cobre. El addon cuenta en el intercambio lo que llega (2/2, 0/1…) y si la propina está pagada.
- Logros nuevos: «Intendencia» y «Artesanos bien pagados».
- Arreglado: nombres de objetos que salían como número (en Forever cambió la función del juego para leerlos).
- El menú lateral se ajusta para no pisar Logros y Ajustes cuando una sección tiene muchos apartados.

Es la primera versión del banco: con hermandades grandes y muchas pestañas aún no está probado del todo. Si algo falla, `/gmk errores` y cuéntanoslo.

---

- **New: Bank section.** What is really inside the guild bank, laid out like the in-game bank (tabs, slots, stacks and gold). It updates every time someone with the addon opens the bank. The guild master chooses in Settings which ranks see each tab.
- **Bank requests:** click an item to request it. It goes to whoever has the new «Hand out bank items» permission; the withdrawal is checked against the bank log and the hand-over in the trade window (or marked manually).
- Deposit requests and the contribution log move from the chest to the Bank section.
- **Orders:** «I'll provide the materials» checkbox with the recipe's reagent list, and a tip in gold, silver and copper. The addon counts what arrives in trades (2/2, 0/1…) and whether the tip was paid.
- New achievements: «Quartermasters» and «Well-Paid Crafters».
- Fixed: item names showing as numbers (Forever changed the game function that reads them).
- The side menu shrinks so it no longer covers Achievements and Settings when a section has many tabs.

This is the first bank release: large guilds with many tabs are not fully tested yet. If something breaks, `/gmk errors` and tell us.

## 1.0.0 · 2026-10

Primera versión estable, ya pública para todo el mundo.

- La medalla «Escudo de la facción» se llama «Escudo» en el estuche (el título que da el oro no cambia).
- API para complementos: `GuildmarkAPI.RegisterToastHandler` permite a otra interfaz pintar los avisos de logro de hermandad a su manera.

---

First stable release, now public for everyone.

- The «Shield of the Faction» medal is shown as «Shield» in the medal case (the gold title is unchanged).
- Add-on API: `GuildmarkAPI.RegisterToastHandler` lets another UI draw the guild achievement toasts its own way.

## 0.9.3 (beta) · 2026-10

- Nuevo: las ocho medallas del perfil tienen arte propio, con una imagen para bronce, plata y oro. También se ven junto al retrato.

---

- New: the eight profile medals have their own art, with an image for bronze, silver and gold. They also show next to the portrait.

## 0.9.2 (beta) · 2026-10

- Nuevo: `/gmk errores` abre una ventana con los errores del addon listos para copiar y avisar de un fallo (también desde Ajustes). No se envía nada a ningún sitio.
- Arreglado: la primera vez que se cargaba el addon podía salir el aviso de Blizzard de «acción bloqueada».
- Cabecera: el marco de la barra de reputación ya encaja con el relleno, y los iconos de insignias y cofre van sin fondo negro.

---

- New: `/gmk errors` opens a window with the addon errors ready to copy and report a bug (also from Settings). Nothing is sent anywhere.
- Fixed: the first time the addon loaded, Blizzard's "action blocked" warning could show up.
- Header: the reputation bar frame now fits the fill, and the badge and chest icons no longer have a black background.

## 0.9.1 (beta) · 2026-10

- Arreglado: la ventana daba un error al abrirse si tenías un encargo al gremio que aún no había aceptado nadie.

---

- Fixed: the window threw an error on opening if you had a guild-wide order nobody had accepted yet.

## 0.9.0 (beta) · 2026-10

Primera versión pública, en beta: casi todo está probado en la beta de WoW Forever, pero
algunas partes solo se podrán comprobar del todo con el juego final (campos de batalla,
mazmorras por estadística, temporada JcJ y el banco de la hermandad con sus permisos).
Si algo falla, avísanos.

- **Hermandad:** quién está conectado y qué hace, fichas de miembros, tribus, clasificación, crónica, cofre de hermandad con proyectos y banco de la hermandad con pedidos.
- **Eventos** con calendario, inscripción por rol y asistencia automática.
- **JcE:** buscador de grupo interno, tiempos y mazmorras completadas.
- **JcJ:** objetivos de caza, cabezas con precio y botín de guerra, auxilio y asaltos a capitales con tu facción, campos de batalla.
- **Facción:** clasificación de hermandades, directorio, récords y Horda contra Alianza.
- **Mercado:** subasta con insignias, gremios de artesanos, encargos y tienda.
- **Perfil:** estuche de medallas, ficha de rol e insignias del retrato.
- **Logros de hermandad** con nivel (1 a 10) y recompensas.
- **Rangos y permisos** decididos por el maestro de la hermandad, y anuncios en el chat de hermandad.

---

First public release, in beta: almost everything has been tested on the WoW Forever beta,
but some parts can only be fully checked on the live game (battlegrounds, dungeons by
statistic, PvP season and the guild bank with its permissions). If something breaks, let us
know.

- **Guild:** who is online and what they are doing, member cards, tribes, ranking, chronicle, a guild chest with projects and the guild bank with requests.
- **Events** with a calendar, sign-up by role and automatic attendance.
- **PvE:** internal group finder, times and completed dungeons.
- **PvP:** hunting targets, bounties and war spoils, calls for help and capital assaults with your faction, battlegrounds.
- **Faction:** guild ranking, directory, records and Horde vs Alliance.
- **Market:** badge auction, crafter guilds, orders and shop.
- **Profile:** medal case, character sheet and portrait badges.
- **Guild achievements** with a level (1 to 10) and rewards.
- **Ranks and permissions** set by the guild master, and announcements in guild chat.
