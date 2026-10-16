"""Original editable Pip vector geometry, in a fixed 512-point artboard.

Coordinates are deliberately shared by the Rive rig and static PDF exports.
The ordered groups paint back to front; each group rotates about its pivot.
"""
from dataclasses import dataclass

@dataclass(frozen=True)
class Shape:
    name: str
    path: str
    color: str
    stroke: str | None = None
    width: float = 0

@dataclass(frozen=True)
class Group:
    name: str
    pivot: tuple[float, float]
    shapes: tuple[Shape, ...]

# Each curve is original production artwork based on the selected Pip brief.
# Sparse broad color planes preserve the face and scarf at 40 points.
GROUPS = [
    Group('Tail', (290, 410), (
        Shape('Tail silhouette', 'M 281 420 C 331 440 410 417 437 363 C 462 315 450 264 417 238 C 409 277 367 289 348 304 C 314 330 302 372 281 420 Z', '#DB692D'),
        Shape('Tail orange plane', 'M 292 409 C 335 417 396 393 420 355 C 440 322 440 279 417 238 C 415 275 375 295 357 308 C 328 332 314 376 292 409 Z', '#F99043'),
        Shape('Cream tail tip', 'M 417 238 C 447 263 455 307 442 342 C 422 349 409 356 391 368 L 400 343 L 372 345 L 391 324 L 367 323 C 390 299 415 278 417 238 Z', '#FFE0B4'),
        Shape('Tail light', 'M 418 248 C 439 276 442 306 434 329 C 426 331 419 334 412 338 C 425 310 429 279 418 248 Z', '#FFECCD'),
    )),
    Group('Legs', (249, 393), (
        Shape('Right leg', 'M 254 357 C 277 359 286 385 283 411 L 285 444 C 293 446 302 454 301 463 C 286 470 267 470 255 466 L 247 411 Z', '#DC6E34'),
        Shape('Right boot', 'M 255 434 C 265 439 273 438 284 435 L 285 444 C 296 447 301 454 301 463 C 286 469 269 470 255 466 Z', '#603B2B'),
        Shape('Left leg', 'M 213 359 C 191 375 188 395 190 421 L 185 447 C 174 450 166 457 167 465 C 182 473 205 471 215 465 L 223 410 L 241 378 Z', '#F58A42'),
        Shape('Left boot', 'M 190 434 C 197 439 209 440 219 434 L 215 465 C 201 472 180 472 167 465 C 167 456 178 450 185 447 Z', '#69422E'),
        Shape('Left toes', 'M 179 462 C 181 457 184 454 188 452 M 191 465 C 191 459 193 455 196 452', 'none', '#402B24', 2.2),
        Shape('Right toes', 'M 274 464 C 274 459 273 455 271 452 M 286 463 C 286 458 284 454 281 451', 'none', '#402B24', 2.2),
    )),
    Group('Body', (240, 394), (
        Shape('Torso', 'M 205 269 C 183 302 177 350 192 381 C 211 414 263 418 282 388 C 297 362 290 304 270 271 Z', '#EE7B39'),
        Shape('Torso sunlight', 'M 213 276 C 189 319 187 356 205 384 C 216 401 237 408 253 402 C 227 372 231 320 250 278 Z', '#F9954A'),
        Shape('Chest', 'M 219 270 C 203 298 205 332 211 362 C 215 386 236 397 250 392 C 254 365 259 332 270 300 L 263 277 Z', '#FFE0B4'),
        Shape('Chest highlight', 'M 229 286 C 219 316 220 350 231 371 C 235 379 242 383 250 383 C 253 355 260 325 266 305 Z', '#FFEACB'),
    )),
    Group('ArmBack', (269, 294), (
        Shape('Back arm', 'M 269 284 C 289 297 295 320 294 343 C 294 357 290 366 283 366 C 275 363 274 354 276 340 C 274 323 267 309 261 300 Z', '#D66A31'),
        Shape('Back paw', 'M 278 340 C 282 343 288 344 294 340 C 296 352 292 367 284 368 C 275 366 273 356 278 340 Z', '#65412E'),
    )),
    Group('ScarfEnds', (270, 275), (
        Shape('Scarf long end', 'M 266 271 C 297 269 317 288 321 310 C 298 307 278 293 266 280 Z', '#226773'),
        Shape('Scarf short end', 'M 270 275 C 280 290 287 308 279 325 C 267 312 261 294 263 279 Z', '#318B94'),
        Shape('Scarf fold', 'M 272 281 C 287 286 298 293 311 302', 'none', '#1D5964', 2),
    )),
    Group('Head', (240, 270), (
        Shape('Head silhouette', 'M 173 137 C 192 118 224 112 248 117 C 274 112 306 127 322 149 C 338 173 339 205 329 223 L 343 220 L 327 239 L 338 241 C 319 256 293 268 263 270 C 227 277 196 266 173 252 L 159 243 L 173 241 L 155 221 L 168 225 C 155 202 156 166 173 137 Z', '#EF803A'),
        Shape('Head sunlight', 'M 179 145 C 202 123 232 122 253 130 C 282 124 310 142 319 162 C 288 146 265 155 250 169 C 233 144 204 141 176 161 Z', '#FFA456'),
        Shape('Cheek mask', 'M 169 211 C 185 192 208 192 225 211 C 236 222 244 230 253 231 C 269 225 281 202 300 203 C 314 203 324 211 329 221 L 340 220 L 325 239 L 335 241 C 309 260 281 269 251 266 C 221 271 190 259 167 241 L 178 240 L 159 222 L 175 226 Z', '#FFE2BC'),
        Shape('Muzzle highlight', 'M 212 231 C 231 219 249 228 256 237 C 268 227 286 225 299 234 C 290 256 267 264 248 261 C 231 259 218 247 212 231 Z', '#FFF0D7'),
        Shape('Nose', 'M 241 229 C 247 225 255 225 261 229 C 262 234 257 238 252 239 C 247 237 242 234 241 229 Z', '#3D2922'),
        Shape('Nose shine', 'M 245 229 C 249 227 254 228 257 229', 'none', '#76513B', 2),
        Shape('Smile', 'M 252 240 C 253 248 264 250 274 242', 'none', '#69402C', 2.4),
        Shape('Smile corner', 'M 272 242 L 276 241', 'none', '#69402C', 2),
    )),
    Group('EarLeft', (191, 148), (
        Shape('Left ear', 'M 165 155 C 149 130 140 91 147 48 C 149 39 153 37 159 42 C 183 61 209 91 217 123 Z', '#E57533'),
        Shape('Left ear cream', 'M 166 143 C 152 115 149 77 153 48 C 174 66 196 93 204 120 Z', '#FFE0B4'),
        Shape('Left ear warm', 'M 173 133 C 166 115 164 97 165 80 C 180 96 190 111 194 122 L 187 121 L 188 133 L 181 130 Z', '#C86C3D'),
    )),
    Group('EarRight', (292, 153), (
        Shape('Right ear', 'M 274 128 C 296 108 330 91 365 90 C 373 90 375 94 372 100 C 361 132 344 160 320 176 Z', '#D36A31'),
        Shape('Right ear cream', 'M 286 131 C 310 113 338 103 366 99 C 355 126 341 149 320 165 Z', '#FFE0B4'),
        Shape('Right ear warm', 'M 309 136 C 325 124 340 117 353 115 C 341 134 331 147 320 154 L 319 145 L 308 147 L 313 140 Z', '#CA7443'),
    )),
    Group('Eyes', (248, 198), (
        Shape('Left eye white', 'M 187 193 C 187 176 194 166 205 167 C 219 168 224 184 221 200 C 219 212 214 219 205 218 C 194 218 188 208 187 193 Z', '#FFF8E8'),
        Shape('Left eye', 'M 201 191 C 202 178 208 173 214 178 C 222 184 222 201 215 209 C 208 216 199 208 201 191 Z', '#36251F'),
        Shape('Left iris', 'M 203 198 C 202 204 207 211 212 209 C 218 207 220 201 218 196 C 215 204 210 205 203 198 Z', '#835033'),
        Shape('Left eye glint', 'M 205 182 C 206 177 211 177 213 181 C 215 186 211 190 207 188 C 205 187 205 185 205 182 Z', '#FFFFFF'),
        Shape('Right eye white', 'M 275 195 C 274 179 282 168 293 171 C 306 174 311 190 306 205 C 303 216 294 221 287 217 C 278 214 276 206 275 195 Z', '#FFF8E8'),
        Shape('Right eye', 'M 285 194 C 284 181 290 175 296 178 C 304 183 307 199 301 209 C 294 219 286 211 285 194 Z', '#36251F'),
        Shape('Right iris', 'M 287 200 C 289 208 294 212 298 208 C 302 205 304 199 301 194 C 300 201 294 205 287 200 Z', '#835033'),
        Shape('Right eye glint', 'M 288 182 C 289 177 294 178 296 181 C 298 186 295 190 291 188 C 288 187 288 184 288 182 Z', '#FFFFFF'),
    )),
    Group('Brows', (248, 165), (
        Shape('Left brow', 'M 185 161 C 192 151 206 149 215 156 C 207 154 194 156 185 161 Z', '#9E4D25'),
        Shape('Right brow', 'M 277 159 C 288 153 300 157 307 167 C 296 160 286 158 277 162 Z', '#9E4D25'),
    )),
    Group('ScarfCollar', (240, 273), (
        Shape('Collar', 'M 192 263 C 211 274 242 278 270 265 C 276 270 276 278 270 284 C 245 297 212 288 194 280 C 190 277 188 269 192 263 Z', '#287C88'),
        Shape('Collar light', 'M 195 266 C 214 275 244 279 269 268 C 270 271 268 275 266 277 C 243 284 217 278 195 272 Z', '#37939A'),
        Shape('Scarf front', 'M 198 281 C 215 286 233 290 250 286 L 218 311 C 211 306 202 292 198 281 Z', '#2F8690'),
        Shape('Scarf knot', 'M 264 269 C 273 266 281 272 280 279 C 278 287 267 288 263 281 C 261 277 261 273 264 269 Z', '#226B77'),
    )),
    Group('ArmFront', (205, 294), (
        Shape('Front arm', 'M 200 286 C 189 297 187 316 193 335 L 205 355 C 210 362 220 357 217 349 L 208 327 C 204 313 209 302 209 295 Z', '#F49249'),
        Shape('Front paw', 'M 200 342 C 205 345 209 345 214 343 L 220 353 C 223 361 216 369 209 366 C 204 365 199 357 198 351 Z', '#68412E'),
        Shape('Paw crease', 'M 209 352 C 210 356 212 360 215 361', 'none', '#402A21', 1.8),
    )),
]
assert len({g.name for g in GROUPS}) == len(GROUPS)
