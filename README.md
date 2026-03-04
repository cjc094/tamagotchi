
# Flutter Tamagotchi (電子雞 App)

This project is a **Flutter Tamagotchi-style virtual pet game**. The user can interact with a virtual pet by feeding it, petting it, and playing a mini‑game to earn coins. The coins can be used in the shop to unlock upgrades and buy food for the pet.

The goal of this project is to practice **Flutter UI design, state management, animations, and simple game mechanics**.

---

# Features

## 🐣 Pet System

The virtual pet has several attributes:

- **Hunger (飽食度)** – increases when feeding cookies
- **Mood (心情值)** – increases when the player pets the pet
- **Growth Stages**

The pet evolves through three stages:

1. 🥚 Egg
2. 🐣 Baby
3. 🐥 Adult

As time passes without interaction, the pet’s **mood will decrease**.

---

## ✋ Pet Interaction

Players can interact with the pet in several ways:

### Petting

- Restores the pet's **mood**
- Triggers a **petting animation** (a hand touching the pet)

### Feeding

- Uses **cookies** purchased from the shop
- Restores the pet's **hunger value**

Interaction is disabled when the stat is already **100%**.

---

# 🎮 Mini Game – Catch the Coins

Players can play a small mini‑game where coins fall from the top of the screen.

Mechanics:

- The player moves a **basket**
- Catch falling **coins**

The coins collected in this mini‑game are used in the shop.

---

# 🛒 Shop System

The shop allows players to buy items using coins.

## Items

### 🍪 Cookies

- Used to feed the pet
- Restores hunger

### 🧺 Basket Upgrades

Basket upgrades make the mini‑game easier.

| Item | Price | Description |
|-----|------|-------------|
| Medium Basket | 100 coins | Larger catching area |
| Large Basket | 300 coins | Even larger basket |

Rules:

- The **Medium Basket must be purchased first**
- The **Large Basket unlocks after the Medium Basket**

---

# ✨ UI Design

The interface is designed similar to a mobile pet game:

- Pet is **centered on screen**
- Interaction buttons are at the **bottom navigation area**

Main actions:

- ✋ Pet
- 🍪 Feed
- 🎮 Play

Animations included:

- Pet idle animation
- Basket upgrade glow effect
- Coin catching feedback

---

# 🧠 Technologies Used

- **Flutter**
- **Dart**
- StatelessWidget / StatefulWidget
- ValueNotifier (for UI updates)
- Simple animation logic

---

# 📂 Project Structure

Example structure:

```
lib/
 ├── main.dart
 ├── screens/
 │   ├── home_screen.dart
 │   ├── game_screen.dart
 │   └── shop_screen.dart
 ├── widgets/
 │   ├── pet_widget.dart
 │   ├── stat_bar.dart
 │   └── basket_widget.dart
 └── models/
     └── pet.dart
```

---

# 🚀 How to Run

1. Install Flutter

https://flutter.dev/docs/get-started/install

2. Clone the project

```
git clone <https://github.com/cjc094/tamagotchi.git>
```

3. Install dependencies

```
flutter pub get
```

4. Run the project

```
flutter run
```