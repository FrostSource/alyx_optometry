[h1]Body Holsters[/h1]

Experience the unseen inconvenience of Gordon's combat as Alyx deals with her macular degeneration by donning a hastily constructed pair of glasses.

[i]This addon require AlyxLib to work.[/i]

[h2]How To Use[/h2]

This addon should work in any map including workshop maps.

You will start with glasses on your face when the map is loaded. They can be taken off by hand or knocked off by movement and interaction with the world. They can be put back on by dropping them on your face just like the face mask.

The amount of vision blur is dependent on your difficulty setting by default. You can change the amount at any time using the console commands below.

If the dropped glasses cannot be found after certain amount of time they will emit a beeping sound and glow to aid your search.

[h2]Console Commands[/h2]

If you don't know how to use the console, follow this guide: https://steamcommunity.com/sharedfiles/filedetails/?id=2040205272

[hr][/hr]
[list]

[*][b]glasses_drop[/b]
Forces the glasses to drop off the player head.

[*][b]glasses_wear[/b]
Forces the glasses to be worn on the player head.

[*][b]glasses_show_hint[/b]
Forces the glasses to display a hint to their location.

[*][b]glasses_blur_amount[/b]
Default = (Depends on difficulty)
Must be a value of 0, 1, 2, or 3. Sets the amount of blur shown when the glasses are not worn, with 0 being the smallest amount and 3 being the biggest amount.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_wear_distance[/b]
Default = 4
Distance from the head at which glasses will always be worn when released.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_accurate_wear_distance[/b]
Default = 10
Distance from the head at which glasses will be worn if accurately aligned with face.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_drop_from_look_down_chance[/b]
Default = 0.05 (5%)
[0-1] (1=100%) chance that the glasses will drop when looking down.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_drop_from_barnacle_grab_chance[/b]
Default = 0.6 (60%)
[0-1] (1=100%) chance that the glasses will drop when the player is grabbed by a barnacle tongue.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_drop_from_head_twitch_chance[/b]
Default = 0.0 (0%)
[0-1] (1=100%) chance that the glasses will drop when the player moves their head quickly.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_drop_from_jump_forward_chance[/b]
Default = 0.02 (2%)
[0-1] (1=100%) chance that the glasses will drop when the player moves/jumps forward quickly.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_drop_from_jump_down_chance[/b]
Default = 0.5 (50%)
[0-1] chance that the glasses will drop when the player jumps down or up a great distance.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_drop_from_damage_chance[/b]
Default = 0.25 (25%)
[0-1] chance that the glasses will drop when the player takes damage.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_hint_delay[/b]
Default = (Depends on difficulty)
Number of seconds to wait before displaying a hint of the glasses location when they're dropped on the ground.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_use_hint_sound[/b]
Default = 1
Glasses will play a sound very [b]glasses_hint_delay[/b] seconds when dropped on the ground to help you locate them while vision is blurry.
[i]This convar is persistent with your save file.[/i]

[*][b]glasses_use_hint_sound[/b]
Default = 1
Glasses will emit a particle after [b]glasses_hint_delay[/b] seconds when dropped to help you locate them while vision is blurry.
[i]This convar is persistent with your save file.[/i]

[/list]

[hr][/hr]
Console commands can be set in the [url=https://help.steampowered.com/faqs/view/7D01-D2DD-D75E-2955]launch options[/url] for Half-Life: Alyx, just put a hyphen before each name and the value after, e.g. [b]-glasses_use_hint_sound 0[/b]
They can also be added to your [b]Half-Life Alyx\game\hlvr\cfg\skill.cfg[/b] file, one per line without the hyphen, e.g. [b]glasses_use_hint_sound 0[/b]

[h2]Source Code[/h2]

GitHub: https://github.com/FrostSource/body_holsters

[h2]Known Issues[/h2]

Ammo displays on visible holstered weapons will show incorrect amount of ammo. Unfortunately I have not found a way to get the current ammo inside a weapon.

Trying to grab a weapon near the face while wearing a mask or respirator will cause the player to accidentally remove the worn item instead of the weapon. Unfortunately I have not found a way to get around this.

Due to the way Half-Life: Alyx works, the multitool will fail to function correctly if equipped by some means other than the weapon selection menu. The multitool is not allowed to be holstered by default for this reason.

Maps without a backpack will function incorrectly.

Holstering can be buggy when the head is mismatched from the real life body (looking sideways while facing forwards). There is no easy way to track where the body is relative to the head.

If a map allows the player to have the same custom weapon in more than one weapon slot, holstering both might cause issues.

[b]body_holsters_require_trigger_to_unholster[/b] will cause rapidfire weapons to shoot if the trigger is held too long after unholstering.

[h2]Getting Help[/h2]

Please feel free to reach out either by commenting below or messaging me on the Discord server!

[url=https://discord.gg/42SC3Wyjv4][img]https://steamuserimages-a.akamaihd.net/ugc/2397692528302959470/036A75FE4B2E8CD2224F8B62E7CEBEE649493C40/?imw=5000&imh=5000&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=false[/img][/url]