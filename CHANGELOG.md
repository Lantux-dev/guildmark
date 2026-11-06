# Cambios · Changelog

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
