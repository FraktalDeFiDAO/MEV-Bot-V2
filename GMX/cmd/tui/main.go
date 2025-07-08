// FILE: cmd/tui/main.go

package main

import (
	"log"
	"os"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type model struct {
	list    list.Model
	spinner spinner.Model
	loading bool
}

func NewModel() model {
	items := []list.Item{
		item("Open Position"),
		item("Close Position"),
		item("Get Position"),
	}
	lst := list.New(items, list.NewDefaultDelegate(), 30, 10)
	lst.Title = "GMXBot TUI"
	return model{
		list:    lst,
		spinner: spinner.New(),
		loading: false,
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "enter":
			m.loading = true
			cmd = m.spinner.Tick
			return m, cmd
		}
	}

	if m.loading {
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}

	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m model) View() string {
	if m.loading {
		return lipgloss.NewStyle().Margin(2, 2).Render("Loading... " + m.spinner.View())
	}
	return m.list.View()
}

type item string

func (i item) Title() string       { return string(i) }
func (i item) Description() string { return "" }
func (i item) FilterValue() string { return string(i) }

func main() {
	if _, err := tea.NewProgram(NewModel()).Run(); err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
}
