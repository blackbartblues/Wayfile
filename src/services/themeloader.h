#pragma once
#include <QObject>
#include <QColor>
#include <QMap>
#include <QStringList>

class ThemeLoader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QColor base READ base NOTIFY themeChanged)
    Q_PROPERTY(QColor mantle READ mantle NOTIFY themeChanged)
    Q_PROPERTY(QColor crust READ crust NOTIFY themeChanged)
    Q_PROPERTY(QColor surface READ surface NOTIFY themeChanged)
    Q_PROPERTY(QColor overlay READ overlay NOTIFY themeChanged)
    Q_PROPERTY(QColor text READ text NOTIFY themeChanged)
    Q_PROPERTY(QColor subtext READ subtext NOTIFY themeChanged)
    Q_PROPERTY(QColor muted READ muted NOTIFY themeChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY themeChanged)
    Q_PROPERTY(QColor success READ success NOTIFY themeChanged)
    Q_PROPERTY(QColor warning READ warning NOTIFY themeChanged)
    Q_PROPERTY(QColor error READ error NOTIFY themeChanged)
    // "Heimdall Unified" obsidian + gold token layer (handoff design).
    // Gold ramp.
    Q_PROPERTY(QColor gold READ gold NOTIFY themeChanged)
    Q_PROPERTY(QColor goldMid READ goldMid NOTIFY themeChanged)
    Q_PROPERTY(QColor goldDeep READ goldDeep NOTIFY themeChanged)
    Q_PROPERTY(QColor goldLight READ goldLight NOTIFY themeChanged)
    // Obsidian surfaces (page = deepest .. raise2 = highest).
    Q_PROPERTY(QColor page READ page NOTIFY themeChanged)
    Q_PROPERTY(QColor bgA READ bgA NOTIFY themeChanged)
    Q_PROPERTY(QColor bgB READ bgB NOTIFY themeChanged)
    Q_PROPERTY(QColor panel READ panel NOTIFY themeChanged)
    Q_PROPERTY(QColor panel2 READ panel2 NOTIFY themeChanged)
    Q_PROPERTY(QColor raise READ raise NOTIFY themeChanged)
    Q_PROPERTY(QColor raise2 READ raise2 NOTIFY themeChanged)
    Q_PROPERTY(QColor line READ line NOTIFY themeChanged)
    Q_PROPERTY(QColor lineSoft READ lineSoft NOTIFY themeChanged)
    Q_PROPERTY(QColor hair READ hair NOTIFY themeChanged)
    // Phase C2 atmosphere tokens. sheen/shadowInk are *base* colours — the
    // various highlight/shadow strengths apply their own alpha at the use
    // site (mirroring how alpha tints of `text` form the hairline language).
    // scrim carries its alpha baked in (#aarrggbb). goldInk is the dark ink
    // painted on gold fills; knob is the warm-white control knob (bridged
    // into Quill in C3).
    Q_PROPERTY(QColor sheen READ sheen NOTIFY themeChanged)
    Q_PROPERTY(QColor shadowInk READ shadowInk NOTIFY themeChanged)
    Q_PROPERTY(QColor scrim READ scrim NOTIFY themeChanged)
    Q_PROPERTY(QColor goldInk READ goldInk NOTIFY themeChanged)
    Q_PROPERTY(QColor knob READ knob NOTIFY themeChanged)

public:
    explicit ThemeLoader(QObject *parent = nullptr);
    void loadTheme(const QString &nameOrPath, const QString &themesDir);
    QColor color(const QString &name) const;

    // Phase C4 live colour editing (the "Colours" settings section). setColor
    // mutates one token in-place and re-emits themeChanged for instant preview;
    // currentColor reads the active value to seed an editor; saveThemeFile
    // serialises every token to a TOML [colors] table so the edited palette can
    // persist as `custom.toml`. colorKeys lists the canonical token set.
    Q_INVOKABLE void setColor(const QString &name, const QColor &c);
    Q_INVOKABLE QColor currentColor(const QString &name) const { return color(name); }
    Q_INVOKABLE bool saveThemeFile(const QString &path) const;
    Q_INVOKABLE QStringList colorKeys() const { return s_defaults.keys(); }
    QColor base() const { return color("base"); }
    QColor mantle() const { return color("mantle"); }
    QColor crust() const { return color("crust"); }
    QColor surface() const { return color("surface"); }
    QColor overlay() const { return color("overlay"); }
    QColor text() const { return color("text"); }
    QColor subtext() const { return color("subtext"); }
    QColor muted() const { return color("muted"); }
    QColor accent() const { return color("accent"); }
    QColor success() const { return color("success"); }
    QColor warning() const { return color("warning"); }
    QColor error() const { return color("error"); }
    QColor gold() const { return color("gold"); }
    QColor goldMid() const { return color("goldMid"); }
    QColor goldDeep() const { return color("goldDeep"); }
    QColor goldLight() const { return color("goldLight"); }
    QColor page() const { return color("page"); }
    QColor bgA() const { return color("bgA"); }
    QColor bgB() const { return color("bgB"); }
    QColor panel() const { return color("panel"); }
    QColor panel2() const { return color("panel2"); }
    QColor raise() const { return color("raise"); }
    QColor raise2() const { return color("raise2"); }
    QColor line() const { return color("line"); }
    QColor lineSoft() const { return color("lineSoft"); }
    QColor hair() const { return color("hair"); }
    QColor sheen() const { return color("sheen"); }
    QColor shadowInk() const { return color("shadowInk"); }
    QColor scrim() const { return color("scrim"); }
    QColor goldInk() const { return color("goldInk"); }
    QColor knob() const { return color("knob"); }
signals:
    void themeChanged();
private:
    QMap<QString, QColor> m_colors;
    static QMap<QString, QColor> s_defaults;
};
