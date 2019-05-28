;;;;;;;;;;;;;;;
;; VARIABLES ;;
;;;;;;;;;;;;;;;

breed [spiders spider] ;; The principle agents of the model
breed [prey a-prey] ;; The agents the spider feeds upon
breed [inquilines inquiline] ;; Agents that invade the web

globals [
  ;; Dynamic globals
  edges ;; The set of patches on the edge of the world
  food ;; How much extra food there is to share between spiders

  ;; Parameters. You can edit these in set-globals
  initial-web-size ;; How big the starting web is
  web-fray-rate ;; The rate at which webbing breaks down
  base-prey-juiciness ;; Determines how juicy (aka how much energy) a size 1 prey is
  max-turtles ;; The total number of agents that can exist at the same time
  metabolism ;; How fast spiders and inquilines go through energy
  time-to-elderhood ;; How long spiders must live for before they can start dying of old age

  ;; The following are parameters for determening the probabilities by which spiders pick certain plans over others
  defend-min ;; The minimum probability for a spider to choose to defend
  defend-mult ;; the multiplier applied to aggression score for defend probability
  capture-min
  capture-mult
  build-min
  build-mult
  parent-max ;; Use max instead of min for parenting due to inverse correlation between aggression and task participation
  parent-mult

  ;; Data globals, used directly or indirectly for collecting information about the simulation
  plans-list ;; The list of possible plans spiders can have. Used for plotting
  max-gen ;; The highest generation number reached this run
  starting-docile ;; The number of starting docile spiders
  starting-aggressive ;; The number of starting aggressive spiders
  proportion-defend-docile ;; List of the number of docile spiders (aggression < 50) defending each tick
  proportion-capture-docile
  proportion-build-docile
  proportion-parent-docile
  proportion-defend-aggressive ;; List of the number of aggressive spiders (aggression >= 50) defending each tick
  proportion-capture-aggressive
  proportion-build-aggressive
  proportion-parent-aggressive

]

spiders-own [
  gen ;; Generation number
  aggression ;; A number between 0 and 100. See documentation for more info
  energy ;; The amount of energy the spider has. The spider dies if this reaches 0
  target ;; The agent or patch the spider is targeting
  plan ;; What the spider wants to do this cycle
  age ;; The current age of the spider
]

prey-own [
  stuck? ;; Boolean, is true if stuck on a web
  age ;; Time in ticks that the prey has been in the simulation
  energy ;; Is converted to spider food or energy once the prey consumed
]

inquilines-own [
  energy ;; See spiders-own
  target
  hunters ;; A list of spiders hunting this inquiline
  run-away? ;; True if being driven off, false otherwise
]

patches-own [
  webbing ;; How dense the webbing is in that patch.
]

;;;;;;;;;;
;; MAIN ;;
;;;;;;;;;;

to setup
  clear-all
  setup-globals
  setup-patches
  setup-agents
  reset-ticks
end

to go
  if not any? spiders [stop] ;; Stop if there are no more spiders
  if count turtles < max-turtles [env-spawn] ;; Have a chance to spawn new prey and inquilines if not at max cap
  update-prey
  update-inquilines
  update-spiders
  update-webbing
  tick
end

;;;;;;;;;;;;;;;;;;;
;; SETUP METHODS ;;
;;;;;;;;;;;;;;;;;;;
; These run at setup

;; A method to define most code-defined globals at setup,
;; mostly so that there is a conveinient place to go and meddle with them later
to setup-globals
  set food 0
  set edges (patch-set
    patches with [pxcor = max-pxcor]
    patches with [pycor = max-pycor]
    patches with [pxcor = min-pxcor]
    patches with [pycor = min-pycor]
  )

  set initial-web-size 0 ;3.5
  set web-fray-rate 0.1
  set base-prey-juiciness 100
  set max-turtles 400
  set metabolism 1
  set time-to-elderhood 200

  set defend-min 1 ;10
  set defend-mult 0.05 ;0.30
  set capture-min 0 ;5
  set capture-mult 0.025 ;0.35
  set build-min 2.5 ;10
  set build-mult 0.10 ;0.25
  set parent-max 30 ;40
  set parent-mult 0.25 ;0.35

  set plans-list (list "defend" "capture" "build" "parent" "none")
  set max-gen 1
  set proportion-defend-docile []
  set proportion-capture-docile []
  set proportion-build-docile []
  set proportion-parent-docile []
  set proportion-defend-aggressive []
  set proportion-capture-aggressive []
  set proportion-build-aggressive []
  set proportion-parent-aggressive []
end

;; A method for changing patch values at setup
to setup-patches
  ask patches [
    ifelse (distancexy 0 0) < initial-web-size
    [set webbing 100]
    [set webbing 0]
  ]

  diffuse webbing 0.75 ;; Spread out the webbing a little and make it look nice
  update-webbing
end

;; For defining breed-wide defaults and creating initial populations at setup
to setup-agents
  ;; Set default shapes
  set-default-shape spiders "spider"
  set-default-shape prey "fly"
  set-default-shape inquilines "inquiline"

  ;; Create initial population of spiders
  make-first-gen initial-population

  ;; Record the number of docile and aggressive spiders created
  set starting-aggressive count spiders with [aggression >= 50]
  set starting-docile count spiders with [aggression < 50]
end

;;;;;;;;;;;;;;;;
;; GO METHODS ;;
;;;;;;;;;;;;;;;;
; These run at each tick

;; To run at the start of go
;; Adds new prey and inquilines to the simulation based on probability
to env-spawn
  if random-float 1 < prey-abundance [create-prey 1 [prey-init]]
  if random-float 1 < inquiline-abundance [create-inquilines 1 [inquiline-init]]
end

;; To run near the beginning of go
;; This controls how prey behaves
to update-prey
  ask prey [
    ;; Wiggle around
    wiggle 40

    ;; If stuck, try to escape
    if stuck? [
      if random 75 > [webbing] of patch-here [set stuck? false]
    ]

    ;; If free...
    if not stuck? [
      ;; Have a chance to fly away once you stay long enough in the area
      if age > 100 and random-float 1 < .01 [die]

      ;; If you're still around, then move ahead
      forward 1

      ;; Check to see if you're now stuck on your new patch
      if random 100 < [webbing] of patch-here [set stuck? true]
    ]

    ;; Increment age
    set age (age + 1)
  ]
end

;; To run in the middle-start of go
;; Controls how inquilines act each tick
to update-inquilines
  ask inquilines [
    ;; If you have no energy this tick, than die of starvation
    if energy <= 0 [die]

    ;; If run-away is true, move to the edge of the screen. Otherwise, look for something to eat
    ifelse run-away?
    [
      ;; Face the target
      face target
      wiggle 20

      ;; If you are not at the edge yet, move forward. Otherwise, despawn
      ifelse not member? patch-here edges [forward 1]
      [
        ask other hunters [scheme] ;; Let the hunters know their goal has been completed
        die
      ]
    ]
    [
      ;; Look for a valid target if you don't already have one.
      ifelse target = nobody [set target min-one-of prey with [stuck?] [distance myself]]
      [if [stuck?] of target = false [set target min-one-of prey with [stuck?] [distance myself]]]

      ;; If you got a target, go for it!
      ifelse target != nobody [
        ;; Face target (w/ some variation)
        face target
        wiggle 20

        ;; If you are in range, eat it! Otherwise, keep moving forward
        ifelse distance target > 1 [forward 1] [eat target]
      ]

      ;; Otherwise, go hang out somewhere comfy (w/ high webbing)
      [
        let comfy-patch max-one-of (patches in-radius 2) [webbing]
        if comfy-patch != patch-here and
        ([webbing] of comfy-patch) >= ([webbing] of patch-here) [
          face comfy-patch
          wiggle 20
          forward 1
        ]
      ]
    ]

    ;; Get hungrier!
    set energy (energy - metabolism)
  ]
end

;; To run in the middle-end of go
;; Controls how spiders act each tick
to update-spiders
  ask spiders [
    ;; If you have no energy this tick, then die
    if energy <= 0 [die]

    ;; If you are getting old, then roll to see if you die
    if death-by-age? and age > time-to-elderhood and random 20 < 1
    [
      set food (food + energy) ;; Cannibalism!
      die
    ]

    update-plan ;; Make a new plan or get a new target, when relevant
    enact-plan ;; Follow the procedure for your plan

    ;; Getting hungrier! Spiders that work need to eat more than spiders that are relaxing
    ifelse plan = "none"
    [set energy (energy - (metabolism / 2))]
    [set energy (energy - metabolism)]

    ;; If low on energy and there is enough food to share, then get some!
    if energy < 15 and food > 0 [
      let share min list food (100 - energy) ;; Figure out how much to take
      set energy (energy + share)
      set food (food - share)
    ]

    set age (age + 1)
  ]
end

;; To run near the end of go
;; The webbing value of each patch decays a little and changes color accordingly
to update-webbing
  ask patches [
    set webbing webbing * (100 - web-fray-rate) / 100 ;; Webs fray and break down over time
    set pcolor scale-color white webbing 0 100
  ]
end

;;;;;;;;;;;;;;;;;;;;
;; TURTLE METHODS ;;
;;;;;;;;;;;;;;;;;;;;
; These can be run by turtles of any kind

;; Makes turtles turn left and right by a random number
;; The upper limit for rng is determined by the magnitude inputted
to wiggle [magnitude]
  left random magnitude
  right random magnitude
end

;; Has the agent eat the target edible, killing the target and transfering energy fron the eatee to the eater
to eat [edible]
  let calories 0

  ask edible [
    set calories energy
    die
  ]

  set energy (energy + calories)
end

;;;;;;;;;;;;;;;;;;;;
;; SPIDER METHODS ;;
;;;;;;;;;;;;;;;;;;;;
; These can only be run by spiders

;; For defining spider variables during creation
to spider-init [aggression-mean sd mother-gen]
  ;; For aggression, pick a random number from a normal distribution with the mean and sd provided
  set aggression int random-normal aggression-mean sd
  set aggression (cap aggression 0 100) ;; Cap aggression between 0 and 100

  set gen mother-gen + 1 ;; The generation of a child is the generation of the mother plus one
  set size 2 ;; Make the spiders more visible
  set energy 100
  set target nobody
  set plan "none"
  set age 0

  if gen > max-gen [set max-gen gen] ;; Update max-gen if this spider's gen is the highest reached

  color-spider
  scheme ;; Decide on your first plan
end

;; Colors spiders based on their aggression value
to color-spider
  ifelse aggression < 50
  [set color scale-color sky aggression -50 50] ;; Docile spiders are more blue
  [set color scale-color red aggression 150 50] ;; Aggressive spiders are more red
  ;; Spiders that are somewhere inbetween will appear almost white
end

;; The action-selection process for spiders.
;; Picks out a plan for the spider to perform based on aggression and chance
to scheme
  ;; Aggressive spiders are more likely to try to defend the colony
  if any? inquilines and random 100 < (defend-min + aggression * defend-mult)[
    set plan "defend"
    set target min-one-of inquilines [distance myself] ;; Go after the inquiline closest to you
    stop
  ]

  ;; Aggressive spiders are more likely to try to capture prey
  if any? prey with [stuck?] and random 100 < (capture-min + aggression * capture-mult) [
    set plan "capture"
    set target min-one-of prey with [stuck?] [distance myself] ;; Go after the stuck prey closest to you
    stop
  ]

  ;; Aggressive spiders are more likely to try to build webs
  let weak-spots patches with [webbing < 50]
  if any? weak-spots and random 100 < (build-min + aggression * build-mult) [
    set plan "build"

    ;; Go after a needy spot close to you, with preference towards spots next to pre-existing strong webs
    let prime-spots weak-spots with [sum [webbing] of neighbors > 65]
    ifelse any? prime-spots
    [set target min-one-of prime-spots [distance myself]]
    [set target min-one-of weak-spots [distance myself]]

    stop
  ]

  ;; Docile spiders are more likely to try to parent
  if food > 100 and count turtles < max-turtles and random 100 < (parent-max - aggression * parent-mult) [
    set plan "parent"
    stop
  ]

  set plan "none" ;; If none of the above plans trigger, just do nothing
end

;; A method for picking a new target, should the old target become unavailable or ineligible
;; If no new target can be found, then have the spider scheme
to find-new-target [agentset]
  ifelse any? agentset
  [set target one-of agentset]
  [scheme]
end

;; Run in update-spiders. Used to try to obtain a new plan when relevant
to update-plan
  ;; Try to think of a plan if you have none
  if plan = "none" [scheme]

  ;; Before doing anything else, make sure your target still exists/is valid
  if plan = "defend" and target = nobody [
    find-new-target inquilines
  ]
  if plan = "capture" and target = nobody [
    find-new-target prey with [stuck?]
  ]

  ;; Before doing any parenting, make sure the maximum turtle limit hasn't been breached
  if plan = "parent" and count turtles > max-turtles [scheme]

end

;; Runs in update-spiders. Makes the spider run the relevant procedure for their plan
to enact-plan
  if plan = "defend" [defend-colony]
  if plan = "capture" [catch-prey]
  if plan = "build" [build-web]
  if plan = "parent" [parental-care]
  if plan = "none" [wiggle 10]
end

;; The web-building procedure of spiders
to build-web
  ;; Face and move towards target patch
  face target
  wiggle 20
  forward 1

  ;; If you get there this tick, build some webs!
  if patch-here = target [
    ask patches in-radius 2 [
      ;; Increase the webbing by 75 plus a quarter of the spider's aggression score
      ;; (Aggressive spiders build webs that keep prey for longer)
      ;; The "- (10 * (distance myself))" is there to make the center patch a little bit stronger in webbing and make it
      ;; a little bit prettier
      set webbing 75 + ([aggression] of myself / 4) - (10 * (distance myself))
      set webbing (cap webbing 0 100) ;; Make sure the value doesn't go past 100
    ]

    ;; Goal complete, get ready to do something else
    scheme
  ]
end

;; The prey capture procedure of spiders
to catch-prey
  ;; Check and make sure the prey is still around. If not, pick a new target or plan and stop this procedure
  if target = nobody [
    find-new-target (prey with [stuck?] in-radius 10)
    stop
  ]

  ;; Check and make sure the prey is still stuck. If not, pick a new target or plan and try again next tick
  ifelse [stuck?] of target = false [find-new-target prey with [stuck?]]
  [
    ;; Face the target (w/ a little variation)
    face target
    wiggle 20

    ;; If you've reached the prey, try to eat it!  Otherwise, move forward
    ifelse distance target > 1 [forward 1]
    ;; Larger prey are harder to catch
    ;; Aggressive spiders have a higher chance of catching prey
    [
      if random 100 < (75 - ([size] of target * 25) + (aggression * 0.45)) [
        eat target

        ;; If full, then share some of your food
        if energy > 100 [
          let excess (energy - 100)
          set food (food + excess)
          set energy (energy - excess)
        ]

        ;; Goal complete, get ready to do something else
        scheme
      ]
    ]
  ]
end

;; The colony defense procedure of spiders
to defend-colony
  ;; Make sure your target is still around. If not, pick a new plan or target and stop this procedure
  if target = nobody [
    find-new-target inquilines
    stop
  ]

  ;; Face the target (w/ a little variation)
  face target
  wiggle 20

  ;; Make sure the inquiline "knows" you're hunting it
  if not member? self ([hunters] of target) [
    ask target [set hunters (turtle-set hunters myself)]
  ]

  let chance 30 - ([size] of target * 10)

  ;; If you're not close enough to your target, move forward. Otherwise, engage the target
  ifelse distance target > 3 [forward 1]
  [
    ;; Try to scare off the target. Larger inquilines are harder to scare off
    ;; Aggressive spiders are better at scaring off inquilines
    if random 100 < chance + (aggression * 0.8) [
      ask target [
        set run-away? true
        set target min-one-of edges [distance myself] ;; Head to the closest edge patch
      ]
    ]

    ;; If you're close enough, try to eat it! Larger inquilines are harder to eat
    ;; Aggressive spiders have a better chance of eating inquilines
    if distance target <= 1 and random 100 < (chance + (aggression * 0.3)) [
      eat target

      ;; If full, then share some of your food
      if energy > 100 [
        let excess (energy - 100)
        set food (food + excess)
        set energy (energy - excess)
      ]

      scheme ;; Goal complete, get ready to do something else
    ]
  ]
end

;; The parental care procedure of spiders
to parental-care
  ;; Try to find somewhere safe and comfy
  let comfy-patch max-one-of (patches in-radius 2) [webbing]

  ;; If the comfiest spot you found isn't the patch you're sitting on, head there next
  if comfy-patch != patch-here and ([webbing] of comfy-patch) > ([webbing] of patch-here) [
    set target comfy-patch
  ]

  ;; Move towards target patch (if its not the one you're standing on right now)
  if is-patch? target [
    face target
    wiggle 20
    forward 1

    ;; If you reach the target this tick, de-select the target
    if patch-here = target [set target nobody]
  ]

  ;; If you have no target at this point (presumably because you're somewhere comfy enough)
  ;; Then try to create a new spider. It will only work if there's enough food in the foodbank and the number of agents doesn't
  ;; exceed the maximum turtle limit
  if target = nobody and food > 100 and count turtles < max-turtles [
    let mother one-of spiders ;; Pick a random spider to be the mother

    ;; Calculate the number of spiders to hatch. Docile spiders generally raise more babies
    let broodcount 1 + random ((100 - aggression) * .10)

    ;; Cap broodcount so that at least one spider is hatched and no more spiders are hatched
    ;; than the foodbank can support
    set broodcount cap broodcount 1 (int food / 100)

    ;; Create a new spider with a personality based on the mother's aggression score
    hatch broodcount [
      ;; If the aggression distribution is binary, then the child will inherit the mother's exact aggression score.
      ;; Otherwise, it can vary from the mother's, with magnitude depending on how high aggression-sd is.
      ifelse aggression-distribution != "binary"
      [spider-init ([aggression] of mother) aggression-sd ([gen] of mother)]
      [spider-init ([aggression] of mother) 0 ([gen] of mother)]

      move-to myself ;; Move the new spider to the parenting spider
      forward 1 ;; Move the new spider a little bit away from the parenting spider
    ]

    set food (food - (100 * broodcount)) ;; Deduct food from the food bank
    scheme ;; Goal complete, get ready to do something else
  ]
end

;;;;;;;;;;;;;;;;;;
;; PREY METHODS ;;
;;;;;;;;;;;;;;;;;;
; These can only be run by prey

;; Like spider-init, but for prey
to prey-init
  ;; Set variables
  set size 2 ;random 3 + 1
  set color black
  set age 0
  set stuck? false
  set energy base-prey-juiciness * size

  ;; Move to a random patch
  move-to one-of patches
end

;;;;;;;;;;;;;;;;;;;;;;;
;; INQUILINE METHODS ;;
;;;;;;;;;;;;;;;;;;;;;;;
; These can only be run by inquilines

;; Like spider-init, but for inquilines
to inquiline-init
  ;; Set variables
  set size 2 ;random 3 + 1
  set color 32.5
  set energy 100
  set target nobody
  set run-away? false
  set hunters turtle-set []

  ;; Move to a random edge patch and face origin
  move-to one-of edges
  facexy 0 0
  forward 0.5
end

;;;;;;;;;;;;;;;;;;;;;
;; UTILITY METHODS ;;
;;;;;;;;;;;;;;;;;;;;;
; Generally useful methods that don't fit elsewhere

;; A method just for making first generation spiders
to make-first-gen [number]
  create-spiders number [
    let aggression-mean init-aggression-mean
    let sd aggression-sd

    ;; Spiders generated under "normal" use init-aggression-mean and aggression-sd directly to get their aggression score
    if aggression-distribution != "normal" [
      ;; Roll to see which side of the aggression spectrum the spider lands on,
      ;; weighted based on init-aggression-mean and aggression-sd
      let roll random-normal aggression-mean sd

      ifelse aggression-distribution != "flat"
      ;; Spiders generated under "binary" and "bimodal" get their aggression-mean set to a set value based on their roll.
      [ifelse roll < 50 [set aggression-mean 5][set aggression-mean 95]]
      [
        ;; Spiders generated under "flat" have equal chance of getting any value that's within the side their on
        ;; So docile spiders have equal chance to get any number between 0-49, and 50-99 for aggressive spiders
        set aggression-mean random 50
        if roll >= 50 [set aggression-mean (aggression-mean + 50)]
      ]
    ]

    ;; Spiders generated under "binary" or "flat" will always get aggression-mean as their aggression score
    if aggression-distribution = "binary" or aggression-distribution = "flat" [set sd 0]

    ;; Now do the actual spider set-up
    spider-init aggression-mean sd 0

    set age random 100 ;; Give the spiders some variation in age
  ]
end

;; Makes a number variable fit within an upper and lower bound
to-report cap [num num-min num-max]
  let new-num min (list num num-max)
  set new-num max (list new-num num-min)
  report new-num
end

;;;;;;;;;;;;;;;;;;
;; TEST METHODS ;;
;;;;;;;;;;;;;;;;;;
; Used to test various aspects of the model. These aren't used in a normal run

;; A "go" method for testing task frequency and proficiency of spiders
to task-test
  if ticks >= 400 [stop] ;; Stop if the test is complete

  ;; For the first 100 ticks (0-99), no flies or inquilines spawn and
  ;; there is (or at least should be) no webs and not enough food to breed. Spiders should build webs or do nothing.

  if ticks < 100 [ask patches [set pcolor scale-color white webbing 0 100]] ;; Update color of patches

  ;; For the next 100 ticks after that (100-199), the enviroment is filled with webs and flies spawn.
  ;; Spiders should capture prey or do nothing.
  if ticks >= 100 and ticks < 200 [
    ;; Fill the world with webbing so prey will get stuck easily
    if ticks = 100 [
      ask patches [
        set webbing 100
        set pcolor scale-color white webbing 0 100
      ]
    ]

    ;; Reset food back to zero
    set food 0

    ;; If there are less than five prey in the world, then spawn more.
    let num-prey count prey
    if num-prey < 5 [create-prey (5 - num-prey) [prey-init]]

    update-prey
  ]

  ;; For the next 100 ticks after that (200-299), inquilines spawn.
  ;; Spiders should defend the colony or do nothing
  if ticks >= 200 and ticks < 300 [
    if any? prey [ask prey [die]] ;; Kill off any remaining prey from the last 100 ticks

    ;; Reset food back to zero
    set food 0

    ;; If there are less than five inquilines in the world, then spawn more
    let num-inquilines count inquilines
    if num-inquilines < 5 [create-inquilines (5 - num-inquilines) [inquiline-init]]

    update-inquilines
  ]

  ;; For the next 100 ticks after that (300-399), the colony's food supply is filled with plenty of food for rearing spiderlings
  ;; Spiders should parent or do nothing
  if ticks >= 300 [
    if any? inquilines [ask inquilines [die]] ;; Kill off any remaining inquilines from the last 100 ticks
    ask spiders with [who > initial-population] [die] ;; Kill off any new spiders born

    set food (count spiders * 1000) ;; Fill the foodbank with enough food to allow for max broodsize for all spiders.
  ]

  ;; Have the spiders pick their plans
  ask spiders [update-plan]

  ;; Record statistics regarding what tasks the spiders are going to perform
  let docile-spiders spiders with [aggression < 50]
  let num-docile count docile-spiders
  let aggressive-spiders spiders with [aggression >= 50]
  let num-aggressive count aggressive-spiders

  if ticks < 100 [
    set proportion-build-docile lput (count docile-spiders with [plan = "build"] / num-docile) proportion-build-docile
    set proportion-build-aggressive lput (count aggressive-spiders with [plan = "build"] / num-aggressive) proportion-build-aggressive
  ]
  if ticks >= 100 and ticks < 200 [
    set proportion-capture-docile lput (count docile-spiders with [plan = "capture"] / num-docile) proportion-capture-docile
    set proportion-capture-aggressive lput (count aggressive-spiders with [plan = "capture"] / num-aggressive) proportion-capture-aggressive
  ]
  if ticks >= 200 and ticks < 300 [
    set proportion-defend-docile lput (count docile-spiders with [plan = "defend"] / num-docile) proportion-defend-docile
    set proportion-defend-aggressive lput (count aggressive-spiders with [plan = "defend"] / num-aggressive) proportion-defend-aggressive
  ]
  if ticks >= 300 [
    set proportion-parent-docile lput (count docile-spiders with [plan = "parent"] / num-docile) proportion-parent-docile
    set proportion-parent-aggressive lput (count aggressive-spiders with [plan = "parent"] / num-aggressive) proportion-parent-aggressive
  ]

  ;; Have the spiders plan act
  ask spiders [enact-plan]

  tick
end
@#$#@#$#@
GRAPHICS-WINDOW
192
10
644
463
-1
-1
8.71
1
10
1
1
1
0
1
1
1
-25
25
-25
25
1
1
1
ticks
30.0

BUTTON
11
161
74
194
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
10
58
182
91
initial-population
initial-population
1
200
20.0
1
1
NIL
HORIZONTAL

BUTTON
120
161
183
194
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
10
91
182
124
init-aggression-mean
init-aggression-mean
0
100
50.0
1
1
NIL
HORIZONTAL

CHOOSER
22
12
172
57
aggression-distribution
aggression-distribution
"normal" "bimodal" "binary" "flat"
1

SLIDER
10
124
182
157
aggression-sd
aggression-sd
0
100
10.0
1
1
NIL
HORIZONTAL

SLIDER
11
199
183
232
prey-abundance
prey-abundance
0.00
1
0.25
0.05
1
prob.
HORIZONTAL

SLIDER
11
231
183
264
inquiline-abundance
inquiline-abundance
0.00
1
0.05
0.05
1
prob.
HORIZONTAL

PLOT
645
12
918
162
Resources
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" "let max-x plot-x-max\nset-plot-x-range 0 max-x"
PENS
"food" 1.0 0 -2674135 true "" "plot food"
"energy" 1.0 0 -13840069 true "" "plot mean [energy] of spiders"
"webbing" 1.0 0 -7500403 true "" "plot mean [webbing] of patches"

PLOT
645
162
918
312
Spider Population
NIL
num spiders
0.0
10.0
0.0
10.0
true
true
";; Code taken and adapted from the \"Crystallization Moving\" sample model\n;; found in Sample Models > Chemistry & Physics > Crystallization\nset-plot-y-range 0 (count spiders)\nif histograms? [set-histogram-num-bars 5]" ""
PENS
"aggressive" 1.0 0 -2674135 true "" "if not histograms? [\nset-plot-pen-mode 0\nplot count spiders with [aggression >= 50]\n]"
"docile" 1.0 0 -13791810 true "" "if not histograms? [\nset-plot-pen-mode 0\nplot count spiders with [aggression < 50]\n]"
"total" 1.0 0 -16777216 true "" "ifelse not histograms? [plot count spiders]\n[\n plot-pen-reset\n set-plot-x-range 0 2\n let index 0\n let personality list \"aggressive\" \"docile\"\n foreach personality [ p ->\n  set-current-plot-pen (item index personality)\n  plot-pen-reset\n  set-plot-pen-mode 1\n  ifelse p = \"aggressive\" \n  [\n    if any? spiders with [aggression >= 50] [\n      plotxy index count spiders with [aggression >= 50]\n    ]\n  ]\n  [\n    if any? spiders with [aggression < 50] [\n      plotxy index count spiders with [aggression < 50]\n    ]\n  ]\n  \n  set index index + 1\n ]\n]"

PLOT
645
312
919
462
Spider Schemes
NIL
num spiders
0.0
5.0
0.0
10.0
true
true
";; Code taken and adapted from the \"Crystallization Moving\" sample model\n;; found in Sample Models > Chemistry & Physics > Crystallization\nset-plot-y-range 0 (count spiders)\nif histograms? [set-histogram-num-bars 5]" ""
PENS
"defend" 1.0 0 -6459832 true "" "if not histograms? [\nset-plot-pen-mode 0\nplot count spiders with [plan = \"defend\"]\n]\n"
"capture" 1.0 0 -2674135 true "" "if not histograms? [\nset-plot-pen-mode 0\nplot count spiders with [plan = \"capture\"]\n]"
"build" 1.0 0 -16777216 true "" "if not histograms? [\nset-plot-pen-mode 0\nplot count spiders with [plan = \"build\"]\n]"
"parent" 1.0 0 -13791810 true "" "if not histograms? [\nset-plot-pen-mode 0\nplot count spiders with [plan = \"parent\"]\n]"
"none" 1.0 0 -7500403 true "" "if not histograms? [\nset-plot-pen-mode 0\nplot count spiders with [plan = \"none\"]\n]"
"histogrammer" 1.0 1 -955883 false "" ";; Code taken and adapted from the \"Crystallization Moving\" sample model\n;; found in Sample Models > Chemistry & Physics > Crystallization\nif not histograms? [stop]\nset-plot-x-range 0 5\nlet index 0\nforeach plans-list [ p ->\n  set-current-plot-pen (item index plans-list)\n  plot-pen-reset\n  set-plot-pen-mode 1\n  if any? spiders with [ plan = p ] [\n    plotxy index count spiders with [ plan = p ]\n  ]\n  set index index + 1\n]"

SWITCH
28
266
166
299
death-by-age?
death-by-age?
0
1
-1000

SWITCH
37
300
158
333
histograms?
histograms?
0
1
-1000

BUTTON
52
429
139
462
NIL
task-test
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
65
354
127
399
max gen
max-gen
17
1
11

@#$#@#$#@
## WHAT IS IT?

This is a model of a colony of _Anelosimus studiosus_ spiders, based primarily on the various assumptions and findings of two different papers: _"Site-specific group selection drives locally adapted group compositions"_ and _"Animal personality aligns task specialization and task proficiency in a spider society"_ (see the References section below). A major hypothesis of this model is that it is the influence of personality on a spider's task preference and performance that, in aggregate, lead to the survival of and adaption towards certain ratios of aggressive:docile spiders in spider colonies. 

To that end, the model is built and designed with these primary goals in mind:

* Have individual spiders perform, based on personality (aggressive vs. docile), tasks at frequency and proficiency similar to the findings of Wright, Holbrook, and Pruitt (2014).

* Survive, thrive, die out, and adapt based on initial starting conditions and aggressive:docile spider ratios, similar with the results for experimental native spider mixtures in Pruitt and Goodnight (2014).

Plus the addition of some secondary goals:

* Explore the consequences of using different methods for assigning aggressiveness (or docility) to spiders (ex. How close to life is a simulated colony using a bimodal distribution vs. a flat distribution of aggression?) 

* Be just generally fun and educational to watch and play around with.

For further information, you can check out the companion "Project Paper" that should be included with this model.

## HOW IT WORKS

When you setup the model, a number of spiders will spawn in the center of the world view. These spiders will be colored differently depending on how aggressive or docile they are: bright red for very aggressive, bright sky blue for very docile, and white for spiders that are perfectly in between. The colony spiders will be more or less likely to perform and succeed at certain tasks depending on how aggressive or docile they are.

While the simulation is running, flies (called prey) and invading spiders (called inquilines) can appear in the world. Prey fly around randomly until they get stuck on webs, at which point they can try to escape until they either succeed or are devoured by a hungry spider. Inquilines will hang out in the web and eat any trapped prey they can reach before the colony can eat them or chase them off. You can tell inquilines apart from the colony spiders by their dark brown coloration and the light brown stripe running down their back.

All the patches in the world are colored different shades of black, grey, or white depending on how much "webbing" is in that area. An area with lots of fresh webbing will appear white while an area with no webs will be black. The more webbing there is in a patch, the more likely it is for prey in that patch to become stuck. Webs age and decay slowly over time, so the colony must continue to perform maintence if they want to continue to catch prey effectively.

Each spider can have a plan to do a certain task, and each tick they will work towards completing that task or, failing that, try to come up with a new plan. The spiders can choose to chase away inquilines, capture trapped prey for food, build or repair webs, or parent some young to adulthood (either their own or another spider's). Spiders can die at the beginning of a tick if they run out of energy or get too old (the latter of which can be disabled). However, there is a stock of food available to the entire colony that individual spiders can add to if they have more than they can eat or take from if they're starting to starve.

For a more in-depth or technical description of the model, please read the companion "Project Paper".

## HOW TO USE IT

When you first open the model you'll notice several options and buttons on the left-hand side of the world view and a few graphs on the right-hand side of the world view. Hopefully the setup button, the go button, and the graphs should be self explanatory.

Let's start with the options, going from top to down. These first four should be configured as you like before you setup and run the model:

* The _aggression-distribution_ chooser lets you select from a number of different options that affect how the aggression scores are generated and distributed amongst the starting spider population. The "binary" option has the additional effect of forcing further offspring to be just as aggressive or docile as their biological parent. The default setting is "binomal".

* The _initial-population_ slider sets how many spiders will be created at setup. The default setting is 20.

* The _init-aggression-mean_ slider sets the midpoint or bias for aggression score generation. Putting this at 50 means a midpoint right in the middle of the scale, or a lack of bias towards one end of the scale over another. Higher values lead to more aggressive spiders, lower values to more docile spiders. The default setting is 50.

* The _aggression-sd_ slider sets the standard deviation used for generating aggression scores for both the initial population and future generations (unless _aggression-distribution_ is "binary", in which case standard deviation is not used). The default setting is 10.

The next four options can be changed at anytime during runtime:

* The _prey-abundance_ slider defines the chance that a new fly will spawn each tick. The default setting is 0.25

* The _inquiline-abundance_ slider does the same thing as the _prey-abundance_ slider, but for inquilines. The default setting is 0.05

* The _death-by-age?_ switch can be toggled on or off depending on whether you want spiders to start dying off once they age past a certain point (which is 200 ticks by default, see _time-to-elderhood_ under _setup-globals_ in the code tab). This is on by default

* The _histograms?_ switch will change some of the graphs to display either histograms or line graphs, depending on whether this is toggled on or off. This is on by default.

Below the options is a monitor for displaying the highest spider generation reached so far in the simulation, in case you're curious to see how high the family tree can grow.

Near the bottom is a _task-test_ button. Clicking this button after doing setup will run a series of scenarios designed to try to elicit certain behaviors from the spiders. It is not very interesting or fun, but is useful for debugging or gathering specific kinds of data or observation.


## CREDITS AND REFERENCES

This model was made by Sharai Wilson in spring of 2019 for COGS 122 at UC Merced.

### Code Snippet Credits:

* Uri Wilensky, for the colorful histogram code from his model "Crystallization Moving", which can be found in the Netlogo Model Library under Sample Models > Chemistry & Physics > Crystallization

### References:

* Pruitt, J., & Goodnight, C. (2014). Site-specific group selection drives locally adapted group compositions. _Nature, 514,_ 359-362. https://doi.org/10.1038/nature13811. [(Link)](https://www.nature.com/articles/nature13811)

* Wright, C., Holbrook, C., & Pruitt, J. (2014). Animal personality aligns task specialization and task proficiency in a spider society. _PNAS, 111 (26),_ 95330-9537. https://doi.org/10.1073/pnas.1400850111. [(Link)](https://www.pnas.org/content/111/26/9533)

### Acknowledgements:

* Paul Smaldino, for showing some cool models and ABM papers to take inspiration from.

* Jonathan Wojcik, for his _Spiderween_ article on social spiders, which I saw first and subsequently felt inspired by. [(Link)](http://www.bogleech.com/spiders/spiders22-social.html)

## CHANGELOG

_Interface last updated 5/25/19_
_Info last updated 5/27/19_
_Code last updated 5/13/19_

* **5/25/19:** Initial release

## LICENSE
This project is licensed under [GPL (GNU Public License) v3](http://www.gnu.org/licenses/gpl-3.0.html)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

fly
true
0
Polygon -1 true false 126 161 94 182 92 221 107 264 145 272 155 271
Polygon -1 true false 174 161 206 182 208 221 193 264 155 272 145 271
Polygon -1 true false 164 111 136 111 111 115 99 129 98 152 112 169 153 177
Polygon -1 true false 136 111 164 111 189 115 201 129 202 152 188 169 147 177
Polygon -1 true false 157 55 134 52 110 57 99 75 101 102 120 113 153 117 177 111
Polygon -1 true false 143 55 166 52 190 57 201 75 199 102 180 113 147 117 123 111
Polygon -7500403 true true 137 111 165 111 183 116 196 127 198 149 187 166 148 177
Polygon -7500403 true true 178 161 203 184 208 220 192 260 160 269 148 267
Polygon -1 true false 150 60 141 53 133 45 151 37 168 45 161 52
Polygon -7500403 true true 157 55 135 55 118 64 106 80 106 97 120 113 153 117 177 111
Polygon -2674135 true false 115 59 104 71 102 94 116 109 126 109 132 93 133 72 126 61 116 59
Polygon -7500403 true true 143 55 165 55 182 64 194 80 194 97 180 113 147 117 123 111
Polygon -2674135 true false 185 59 196 71 198 94 184 109 174 109 168 93 167 72 174 61 184 59
Polygon -7500403 true true 150 60 145 53 136 46 150 41 164 45 156 53
Polygon -7500403 true true 164 111 136 111 118 116 105 127 103 149 114 166 153 177
Rectangle -7500403 true true 121 161 180 254
Polygon -7500403 true true 126 161 101 184 96 220 112 260 144 269 156 267
Polygon -1 false false 123 113 72 131 34 183 51 247 91 244 113 199 137 133
Polygon -1 false false 177 113 228 131 266 183 249 247 209 244 187 199 163 133

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

inquiline
true
0
Polygon -16777216 true false 136 210 142 194 105 195 80 212 106 287 54 209 89 176 136 180
Polygon -16777216 true false 164 210 158 194 195 195 220 212 194 287 246 209 211 176 164 180
Polygon -16777216 true false 139 183 97 171 64 184 30 244 45 168 97 150 137 160
Polygon -16777216 true false 161 183 203 171 236 184 270 244 255 168 203 150 163 160
Polygon -16777216 true false 127 112 97 98 88 71 72 22 70 74 85 118 119 130
Polygon -16777216 true false 137 140 86 123 68 110 43 68 53 127 83 148 135 154
Polygon -16777216 true false 163 140 214 123 232 110 257 68 247 127 217 148 162 155
Polygon -16777216 true false 133 258 102 241 92 209 96 194 108 170 127 154 115 132 119 120 131 102 165 102 176 116 182 134 171 154 190 171 199 195 207 209 195 241 166 258
Line -7500403 true 167 109 170 90
Line -7500403 true 170 91 156 88
Line -7500403 true 130 91 144 88
Line -7500403 true 133 109 130 90
Polygon -7500403 true true 164 210 158 194 195 195 225 210 195 285 240 210 210 180 164 180
Polygon -16777216 true false 171 112 203 98 212 71 228 22 230 74 215 118 181 130
Polygon -7500403 true true 163 140 214 129 234 114 255 74 242 126 216 143 164 152
Polygon -7500403 true true 161 183 203 167 239 180 268 239 249 171 202 153 163 162
Polygon -7500403 true true 133 117 93 102 84 71 73 27 73 72 88 115 133 132
Polygon -7500403 true true 134 255 104 240 96 210 98 196 114 171 134 150 119 137 119 120 134 105 164 105 179 120 179 135 164 150 185 173 199 195 203 210 194 240 164 255
Polygon -7500403 true true 167 117 207 102 216 71 227 27 227 72 212 117 167 132
Polygon -7500403 true true 137 140 86 129 66 114 45 74 58 126 84 143 136 152
Polygon -7500403 true true 139 183 97 167 61 180 32 239 51 171 98 153 137 162
Polygon -7500403 true true 136 210 142 194 105 195 75 210 105 285 60 210 90 180 136 180
Polygon -6459832 true false 152 149 144 150 132 171 130 194 131 220 137 239 146 247 154 246 158 211
Polygon -6459832 true false 146 149 154 150 166 171 168 194 167 220 161 239 152 247 144 246 140 211

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

spider
true
0
Polygon -16777216 true false 136 210 142 194 105 195 80 212 106 287 54 209 89 176 136 180
Polygon -16777216 true false 164 210 158 194 195 195 220 212 194 287 246 209 211 176 164 180
Polygon -16777216 true false 139 183 97 171 64 184 30 244 45 168 97 150 137 160
Polygon -16777216 true false 161 183 203 171 236 184 270 244 255 168 203 150 163 160
Polygon -16777216 true false 127 112 97 98 88 71 72 22 70 74 85 118 119 130
Polygon -16777216 true false 137 140 86 123 68 110 43 68 53 127 83 148 135 154
Polygon -16777216 true false 163 140 214 123 232 110 257 68 247 127 217 148 162 155
Polygon -16777216 true false 133 258 102 241 92 209 96 194 108 170 127 154 115 132 119 120 131 102 165 102 176 116 182 134 171 154 190 171 199 195 207 209 195 241 166 258
Line -7500403 true 167 109 170 90
Line -7500403 true 170 91 156 88
Line -7500403 true 130 91 144 88
Line -7500403 true 133 109 130 90
Polygon -7500403 true true 164 210 158 194 195 195 225 210 195 285 240 210 210 180 164 180
Polygon -16777216 true false 171 112 203 98 212 71 228 22 230 74 215 118 181 130
Polygon -7500403 true true 163 140 214 129 234 114 255 74 242 126 216 143 164 152
Polygon -7500403 true true 161 183 203 167 239 180 268 239 249 171 202 153 163 162
Polygon -7500403 true true 133 117 93 102 84 71 73 27 73 72 88 115 133 132
Polygon -7500403 true true 134 255 104 240 96 210 98 196 114 171 134 150 119 137 119 120 134 105 164 105 179 120 179 135 164 150 185 173 199 195 203 210 194 240 164 255
Polygon -7500403 true true 167 117 207 102 216 71 227 27 227 72 212 117 167 132
Polygon -7500403 true true 137 140 86 129 66 114 45 74 58 126 84 143 136 152
Polygon -7500403 true true 139 183 97 167 61 180 32 239 51 171 98 153 137 162
Polygon -7500403 true true 136 210 142 194 105 195 75 210 105 285 60 210 90 180 136 180

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Colony Composition (Bimodal &amp; Binary)" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="400"/>
    <metric>starting-docile</metric>
    <metric>starting-aggressive</metric>
    <metric>count spiders</metric>
    <metric>count spiders with [aggression &lt; 50]</metric>
    <metric>count spiders with [aggression &gt;= 50]</metric>
    <metric>max-gen</metric>
    <enumeratedValueSet variable="aggression-distribution">
      <value value="&quot;bimodal&quot;"/>
      <value value="&quot;binary&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="inquiline-abundance" first="0" step="0.05" last="1"/>
    <steppedValueSet variable="prey-abundance" first="0" step="0.05" last="1"/>
    <enumeratedValueSet variable="random-seed">
      <value value="11111954"/>
      <value value="10092010"/>
      <value value="8888"/>
      <value value="591435"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aggression-sd">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-population">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-aggression-mean">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="death-by-age?">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Colony Composition (Normal)" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="400"/>
    <metric>starting-docile</metric>
    <metric>starting-aggressive</metric>
    <metric>count spiders</metric>
    <metric>count spiders with [aggression &lt; 50]</metric>
    <metric>count spiders with [aggression &gt;= 50]</metric>
    <metric>max-gen</metric>
    <enumeratedValueSet variable="aggression-distribution">
      <value value="&quot;normal&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="inquiline-abundance" first="0" step="0.05" last="1"/>
    <steppedValueSet variable="prey-abundance" first="0" step="0.05" last="1"/>
    <enumeratedValueSet variable="random-seed">
      <value value="8151952"/>
      <value value="10092010"/>
      <value value="12102015"/>
      <value value="591435"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aggression-sd">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-population">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-aggression-mean">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="death-by-age?">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Colony Composition (Flat)" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="400"/>
    <metric>starting-docile</metric>
    <metric>starting-aggressive</metric>
    <metric>count spiders</metric>
    <metric>count spiders with [aggression &lt; 50]</metric>
    <metric>count spiders with [aggression &gt;= 50]</metric>
    <metric>max-gen</metric>
    <enumeratedValueSet variable="aggression-distribution">
      <value value="&quot;flat&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="inquiline-abundance" first="0" step="0.05" last="1"/>
    <steppedValueSet variable="prey-abundance" first="0" step="0.05" last="1"/>
    <enumeratedValueSet variable="random-seed">
      <value value="8151962"/>
      <value value="10041966"/>
      <value value="12102015"/>
      <value value="591435"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aggression-sd">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-population">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-aggression-mean">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="death-by-age?">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Seed Test" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>type aggression-distribution 
type ": "
print (starting-aggressive + 1) / (starting-docile + 1)</final>
    <timeLimit steps="1"/>
    <metric>(starting-aggressive + 1) / (starting-docile + 1)</metric>
    <enumeratedValueSet variable="random-seed">
      <value value="591435"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aggression-distribution">
      <value value="&quot;bimodal&quot;"/>
      <value value="&quot;binary&quot;"/>
      <value value="&quot;normal&quot;"/>
      <value value="&quot;flat&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="inquiline-abundance">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aggression-sd">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="death-by-age?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prey-abundance">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-population">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="histograms?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-aggression-mean">
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Task Participation Frequency" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>task-test</go>
    <timeLimit steps="400"/>
    <metric>mean proportion-defend-docile</metric>
    <metric>mean proportion-capture-docile</metric>
    <metric>mean proportion-build-docile</metric>
    <metric>mean proportion-parent-docile</metric>
    <metric>mean proportion-defend-aggressive</metric>
    <metric>mean proportion-capture-aggressive</metric>
    <metric>mean proportion-build-aggressive</metric>
    <metric>mean proportion-parent-aggressive</metric>
    <enumeratedValueSet variable="aggression-distribution">
      <value value="&quot;binary&quot;"/>
      <value value="&quot;bimodal&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="inquiline-abundance">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prey-abundance">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-seed">
      <value value="8151952"/>
      <value value="11111954"/>
      <value value="7021998"/>
      <value value="8032009"/>
      <value value="8151962"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aggression-sd">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-population">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-aggression-mean">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="death-by-age?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="More Task Participation Frequencies" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>task-test</go>
    <timeLimit steps="400"/>
    <metric>mean proportion-defend-docile</metric>
    <metric>mean proportion-capture-docile</metric>
    <metric>mean proportion-build-docile</metric>
    <metric>mean proportion-parent-docile</metric>
    <metric>mean proportion-defend-aggressive</metric>
    <metric>mean proportion-capture-aggressive</metric>
    <metric>mean proportion-build-aggressive</metric>
    <metric>mean proportion-parent-aggressive</metric>
    <enumeratedValueSet variable="aggression-distribution">
      <value value="&quot;binary&quot;"/>
      <value value="&quot;bimodal&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="inquiline-abundance">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prey-abundance">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="random-seed" first="0" step="20004" last="88888888"/>
    <enumeratedValueSet variable="aggression-sd">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-population">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-aggression-mean">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="death-by-age?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
