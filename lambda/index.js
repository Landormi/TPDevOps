exports.handler = async () => {
    const date = new Date().toLocaleTimeString("fr-FR", { timeZone: "Europe/Paris" });
    const response = `Hello World ! Ici Maxime et Tanguy, à ${date}`;
    console.log(response);
    return {
        statusCode: 200,
        body: response
    };
};
