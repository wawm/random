package main

import (
        "fmt"
        "os"
        "os/exec"
        "strings"
)

func main() {

        myCommand2 := "apt -qq list apache2 2> /dev/null | grep -i installed | awk '{print $4}'"
        expectedOutput := "[installed]"
        myCommandOutput, OutputErr := exec.Command("sh", "-c", myCommand2).Output()

        myCommandOutputStr := strings.TrimSpace(string(myCommandOutput))

        if OutputErr != nil {
                fmt.Println("Error in Command, please debug manually")
                return
        }

        if myCommandOutputStr == expectedOutput {
                fmt.Println("Package found, exiting")
        } else {
                fmt.Println("Package not found, installing...")
                upgrade()
        }

}

func upgrade() {

        myCommand := "apt install -y apache2"
        fmt.Println("Installation of apache2 on Ubuntu")
        output, err := exec.Command("sh", "-c", myCommand).Output()

        if err != nil {

                fmt.Println("Error")
                return
        }

        upgrade, fileErr := os.Create("upgrade.output")
        if err != nil {
                fmt.Println(fileErr)
                return
        }
        fmt.Fprintf(upgrade, "%s\n", output)
        fmt.Println(string(output))
}
